# The AX210 boots in the "world" regulatory domain (country 00 → no HT → 54
  # Mbit/s) and associates immediately, locking the legacy rate in at association
  # time. Only after receiving enough beacons does its firmware adopt country US
  # from the gateway's country IE (~30-45s later) — but the existing association
  # never renegotiates. So we wait for the firmware to actually reach US, then
  # force one re-association, which comes up at full HE / 160 MHz rates.
  #
  # The NM dispatcher only kicks the service (systemctl --no-block talks to systemd,
  # not NM, so there's no reentrancy/deadlock). The service does the work off the
  # boot critical path, so its up-to-90s wait never delays login.
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "wifi-regdom-trigger" ''
        [ "$1" = "wlp6s0" ] || exit 0
        [ "$2" = "up" ] || exit 0
        exec ${pkgs.systemd}/bin/systemctl start --no-block wifi-regdom-fix.service
      '';
    }
  ];

  systemd.services.wifi-regdom-fix = {
    description = "Re-associate AX210 once its firmware adopts the US regulatory domain";
    serviceConfig.Type = "oneshot";
    script = ''
      lock=/run/wifi-regdom-fixed
      [ -e "$lock" ] && exit 0

      phy=$(${pkgs.iw}/bin/iw dev wlp6s0 info 2>/dev/null | ${pkgs.gawk}/bin/awk '/wiphy/ {print $2}')
      [ -n "$phy" ] || exit 0

      # Wait up to 90s for the firmware to switch from country 00 to US.
      for _ in $(seq 1 90); do
        ${pkgs.iw}/bin/iw reg get 2>/dev/null | grep -A1 "phy#$phy" | grep -q "country US" && break
        sleep 1
      done

      # One attempt per boot regardless of outcome (cleared on reboot via /run).
      touch "$lock"

      # If the link is still on the legacy (no HT) association it negotiated while
      # at country 00, re-associate now that the domain is US.
      if ${pkgs.iw}/bin/iw dev wlp6s0 info 2>/dev/null | grep -q "no HT"; then
        ${pkgs.networkmanager}/bin/nmcli device disconnect wlp6s0
        sleep 3
        ${pkgs.networkmanager}/bin/nmcli device connect wlp6s0
      fi
    '';
  };
