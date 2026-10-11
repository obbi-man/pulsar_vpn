cmake_minimum_required(VERSION 3.22.1)
project(customshield_tun2socks)

set(CMAKE_CXX_STANDARD 17)

add_library(customshield_tun2socks SHARED tun2socks_jni.cpp)

find_library(log-lib log)
target_link_libraries(customshield_tun2socks ${log-lib})

# Optional: vendor hev-socks5-tunnel via tool/fetch_tun2socks.sh
set(HEV_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/hev-socks5-tunnel)
if (EXISTS ${HEV_DIR}/src/hev-main.c OR EXISTS ${HEV_DIR}/CMakeLists.txt)
  message(STATUS "hev-socks5-tunnel found — enabling HAVE_HEV_SOCKS5_TUNNEL")
  target_compile_definitions(customshield_tun2socks PRIVATE HAVE_HEV_SOCKS5_TUNNEL)
  # Prefer hev's own build; if present as static lib:
  if (EXISTS ${HEV_DIR}/lib/libhev-socks5-tunnel.a)
    target_link_libraries(customshield_tun2socks ${HEV_DIR}/lib/libhev-socks5-tunnel.a)
  elseif (EXISTS ${HEV_DIR}/CMakeLists.txt)
    add_subdirectory(${HEV_DIR} hev-socks5-tunnel)
    target_link_libraries(customshield_tun2socks hev-socks5-tunnel)
  endif()
else()
  message(WARNING "hev-socks5-tunnel not vendored; building JNI stub. Run flutter/tool/fetch_tun2socks.sh")
  # Allow APK layout / MethodChannel testing without native hev.
  target_compile_definitions(customshield_tun2socks PRIVATE CS_TUN2SOCKS_STUB)
endif()
