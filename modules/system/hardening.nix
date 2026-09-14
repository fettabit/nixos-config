{...}: {
  # Kernel-level hardening beyond the NixOS defaults (which already give
  # ptrace_scope=1, dmesg/kptr restrict, unprivileged_bpf_disabled=2 and all
  # fs.protected_*). Everything here is a no-op for a single-NIC desktop's
  # normal traffic; it only closes spoofing/redirect paths.
  boot.kernel.sysctl = {
    # Drop packets whose source address could not have arrived on this
    # interface (strict reverse-path filtering; single NIC, no VPN routing).
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    # We are not a router: neither accept nor emit ICMP redirects.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    # Source-routed packets are never legitimate here.
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
  };

  # kexec_load_disabled=1 (+ nohibernate): a root process cannot swap in an
  # unsigned kernel underneath Secure Boot. Hibernation is already unused
  # (no resumeDevice; the session/launcher "sleep" actions suspend).
  security.protectKernelImage = true;
}
