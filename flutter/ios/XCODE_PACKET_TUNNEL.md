# Adding the PacketTunnel Xcode target

Flutter's generated `ios/Runner.xcodeproj` does not yet include the Network
Extension target. After `flutter create`, open the project in Xcode and:

1. **File → New → Target → Network Extension → Packet Tunnel Provider**
2. Product Name: `PacketTunnel`
3. Bundle Identifier: `com.customshield.customshield.PacketTunnel`
4. Replace generated Swift with `ios/PacketTunnel/PacketTunnelProvider.swift`
5. Set entitlements file to `ios/PacketTunnel/PacketTunnel.entitlements`
6. Set Info.plist to `ios/PacketTunnel/Info.plist` (or merge NSExtension keys)
7. Embed the extension in the Runner target (Frameworks, Libraries, and Embedded Content)
8. Link `libcustomshield.a` + headers from `custom-protocol/dist/libs/ios/`
9. Enable **Network Extensions** + **App Groups**
   (`group.com.customshield.customshield`) on the Apple Developer portal and in
   both Runner + PacketTunnel signing settings

Repeat similarly for `macos/PacketTunnel`.
