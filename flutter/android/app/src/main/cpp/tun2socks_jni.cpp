#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

#define LOG_TAG "cs_tun2socks"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/*
 * Optional integration with hev-socks5-tunnel.
 * When HEAVY_SOCKS_TUNNEL is defined (see CMakeLists.txt), we call into hev.
 * Otherwise we provide a clear stub that returns an error so the Kotlin layer
 * can surface a actionable message — still production-shaped API surface.
 */
#if defined(HAVE_HEV_SOCKS5_TUNNEL)
extern "C" {
int hev_socks5_tunnel_main(const char *config_path, int tun_fd);
void hev_socks5_tunnel_quit(void);
}
#endif

namespace {
std::mutex g_mu;
std::atomic<bool> g_running{false};
std::thread g_worker;
std::string g_config_path;
}  // namespace

static int write_hev_config(const char *path, const char *socks_uri,
                            const char *tun_addr, const char *tun_mask) {
  // Minimal YAML for hev-socks5-tunnel.
  // socks_uri format: socks5://host:port
  std::string uri(socks_uri ? socks_uri : "");
  std::string host = "127.0.0.1";
  int port = 18080;
  auto pos = uri.rfind("://");
  if (pos != std::string::npos) {
    auto rest = uri.substr(pos + 3);
    auto colon = rest.rfind(':');
    if (colon != std::string::npos) {
      host = rest.substr(0, colon);
      port = std::atoi(rest.substr(colon + 1).c_str());
    } else {
      host = rest;
    }
  }

  FILE *f = std::fopen(path, "w");
  if (!f) return -1;
  std::fprintf(f,
               "tunnel:\n"
               "  name: customshield\n"
               "  mtu: 8500\n"
               "socks5:\n"
               "  port: %d\n"
               "  address: %s\n"
               "  udp: 'udp'\n",
               port, host.c_str());
  std::fclose(f);
  (void)tun_addr;
  (void)tun_mask;
  return 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_customshield_customshield_vpn_Tun2SocksBridge_nativeStart(
    JNIEnv *env, jclass, jint tun_fd, jstring j_socks_uri, jstring j_tun_addr,
    jstring j_tun_mask) {
  std::lock_guard<std::mutex> lock(g_mu);
  if (g_running.load()) {
    return 0;
  }

  const char *socks = env->GetStringUTFChars(j_socks_uri, nullptr);
  const char *addr = env->GetStringUTFChars(j_tun_addr, nullptr);
  const char *mask = env->GetStringUTFChars(j_tun_mask, nullptr);

#if defined(HAVE_HEV_SOCKS5_TUNNEL)
  g_config_path = "/data/local/tmp/customshield-hev.yml";
  // Prefer app-private path when available — Kotlin should pass cache dir in
  // a future revision; for now use a relative path under /data/data via fd only.
  g_config_path = "hev-customshield.yml";
  if (write_hev_config(g_config_path.c_str(), socks, addr, mask) != 0) {
    LOGE("failed to write hev config");
    env->ReleaseStringUTFChars(j_socks_uri, socks);
    env->ReleaseStringUTFChars(j_tun_addr, addr);
    env->ReleaseStringUTFChars(j_tun_mask, mask);
    return -1;
  }

  int fd = tun_fd;
  g_running = true;
  g_worker = std::thread([fd]() {
    LOGI("hev-socks5-tunnel starting on fd=%d", fd);
    hev_socks5_tunnel_main(g_config_path.c_str(), fd);
    g_running = false;
    LOGI("hev-socks5-tunnel exited");
  });
  g_worker.detach();

  env->ReleaseStringUTFChars(j_socks_uri, socks);
  env->ReleaseStringUTFChars(j_tun_addr, addr);
  env->ReleaseStringUTFChars(j_tun_mask, mask);
  return 0;
#else
  LOGE("HAVE_HEV_SOCKS5_TUNNEL not enabled. Run tool/fetch_tun2socks.sh and rebuild.");
  (void)tun_fd;
  (void)socks;
  (void)addr;
  (void)mask;
  env->ReleaseStringUTFChars(j_socks_uri, socks);
  env->ReleaseStringUTFChars(j_tun_addr, addr);
  env->ReleaseStringUTFChars(j_tun_mask, mask);
  // Return success in "soft" mode only when CS_TUN2SOCKS_STUB=1 is compile-defined
  // for CI layout checks — production builds must link hev.
#if defined(CS_TUN2SOCKS_STUB)
  LOGI("stub tun2socks accept (TUN fd=%d) — not forwarding packets", (int)tun_fd);
  g_running = true;
  return 0;
#else
  return -2;
#endif
#endif
}

extern "C" JNIEXPORT void JNICALL
Java_com_customshield_customshield_vpn_Tun2SocksBridge_nativeStop(JNIEnv *,
                                                                  jclass) {
  std::lock_guard<std::mutex> lock(g_mu);
#if defined(HAVE_HEV_SOCKS5_TUNNEL)
  if (g_running.load()) {
    hev_socks5_tunnel_quit();
  }
#endif
  g_running = false;
}
