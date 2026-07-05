This is a repo to document a bug and workaround in the Xfinity XB8 gateway's 802.11d Wi-Fi implementation.

The Bug:
Not all data frames broadcasted by the contain the country IE leading some clients (namely Intel AX200/AX210/AX211 on linux) to connect with a regdom code set at 00 forcing clients to operate at legacy wireless a speeds of 54mbps.

I am not exactly sure what behavior casuses the XB8 to start or stop broadcasting the country IE, but I have observed it starting after changing the SSID and Password.

The workaround:
The workaround was made with the assistance of Claude. I have only tested the NixOS specific configuration. I will not maintain or support this script in its Bash or NixOS implementation, but I want it to serve as a reference for any Xfinity engineers or end users encountering the same error.

https://forums.xfinity.com/conversations/your-home-network/bug-report-xb8-gateway-does-not-broadcast-80211d-country-ie-in-default-state-wifi-6-clients-capped-at-54-mbps/6a332f77ee5da4640000eaff
