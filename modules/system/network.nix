{...}: {
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # DNS: systemd-resolved talking DNS-over-TLS to Quad9 (no logging, blocks
  # known-malicious domains, DNSSEC-validating). Strict DoT — never falls back
  # to plaintext. "~." routes every query to these global servers instead of
  # the per-link router DNS, and NetworkManager stops importing the DHCP
  # servers at all, so the router (which speaks no TLS) is never consulted.
  # Cost: LAN hostnames handed out by the router no longer resolve — mDNS
  # (.local) still does via resolved.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSOverTLS = "true";
      DNSSEC = "allow-downgrade";
      Domains = ["~."];
      FallbackDNS = ["9.9.9.9#dns.quad9.net" "149.112.112.112#dns.quad9.net"];
    };
  };
  networking.nameservers = [
    "9.9.9.9#dns.quad9.net"
    "149.112.112.112#dns.quad9.net"
    "2620:fe::fe#dns.quad9.net"
    "2620:fe::9#dns.quad9.net"
  ];
  networking.networkmanager = {
    dns = "systemd-resolved";
    connectionConfig = {
      "ipv4.ignore-auto-dns" = true;
      "ipv6.ignore-auto-dns" = true;
    };
  };
}
