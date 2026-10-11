import { readFile } from "node:fs/promises";
import path from "node:path";
import { randomBytes, randomUUID } from "node:crypto";
import type { Client, ConnectConfig } from "ssh2";

async function loadSsh2() {
  // ssh2 ships native bindings — keep it out of the bundler graph.
  return import("ssh2");
}

export type ProvisionCredentials = {
  host: string;
  port: number;
  username: string;
  password: string;
};

export type ProvisionResult = {
  serverUuid: string;
  secretKey: string;
  stdout: string;
};

export type ProvisionProgress =
  | "ssh_check"
  | "upload"
  | "docker_deploy"
  | "success";

function execCommand(
  conn: Client,
  command: string,
): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    conn.exec(command, (err, stream) => {
      if (err) {
        reject(err);
        return;
      }
      let stdout = "";
      let stderr = "";
      stream
        .on("close", (code: number | null) => {
          resolve({ code, stdout, stderr });
        })
        .on("data", (data: Buffer) => {
          stdout += data.toString("utf8");
        });
      stream.stderr.on("data", (data: Buffer) => {
        stderr += data.toString("utf8");
      });
    });
  });
}

async function connectSsh(config: ConnectConfig): Promise<Client> {
  const { Client } = await loadSsh2();
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const timer = setTimeout(() => {
      conn.end();
      reject(new Error("SSH connection timed out"));
    }, 20_000);

    conn
      .on("ready", () => {
        clearTimeout(timer);
        resolve(conn);
      })
      .on("error", (err: Error) => {
        clearTimeout(timer);
        reject(err);
      })
      .connect(config);
  });
}

async function uploadFile(
  conn: Client,
  localPath: string,
  remotePath: string,
): Promise<void> {
  const content = await readFile(localPath);
  await new Promise<void>((resolve, reject) => {
    conn.sftp((err, sftp) => {
      if (err) {
        reject(err);
        return;
      }
      const writeStream = sftp.createWriteStream(remotePath, {
        mode: 0o755,
      });
      writeStream.on("close", () => resolve());
      writeStream.on("error", reject);
      writeStream.end(content);
    });
  });
}

export async function provisionVps(
  creds: ProvisionCredentials,
  onProgress?: (step: ProvisionProgress) => void,
): Promise<ProvisionResult> {
  const serverUuid = randomUUID();
  const secretKey = randomBytes(32).toString("hex");
  const protocolDir = path.join(process.cwd(), "custom-protocol");
  const remoteDir = "/tmp/customshield-upload";

  onProgress?.("ssh_check");
  let conn: Client;
  try {
    conn = await connectSsh({
      host: creds.host,
      port: creds.port,
      username: creds.username,
      password: creds.password,
      readyTimeout: 20_000,
      tryKeyboard: false,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "SSH connection failed";
    throw new Error(`SSH connection error: ${message}`);
  }

  try {
    onProgress?.("upload");
    await execCommand(conn, `mkdir -p ${remoteDir}`);
    await uploadFile(
      conn,
      path.join(protocolDir, "server.go"),
      `${remoteDir}/server.go`,
    );
    await uploadFile(
      conn,
      path.join(protocolDir, "deploy-proto.sh"),
      `${remoteDir}/deploy-proto.sh`,
    );

    onProgress?.("docker_deploy");
    const deployCmd = [
      `cd ${remoteDir}`,
      "chmod +x deploy-proto.sh",
      `CS_SECRET_KEY='${secretKey}' bash ./deploy-proto.sh`,
    ].join(" && ");

    const { code, stdout, stderr } = await execCommand(conn, deployCmd);
    const combined = `${stdout}\n${stderr}`;

    if (!combined.includes("SUCCESS_DEPLOYS")) {
      throw new Error(
        `Deploy script did not report SUCCESS_DEPLOYS (exit ${code ?? "unknown"}): ${combined.slice(-2000)}`,
      );
    }

    onProgress?.("success");
    return { serverUuid, secretKey, stdout: combined };
  } finally {
    conn.end();
  }
}
