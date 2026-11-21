# gcp-wireguard-vpn

Your own WireGuard VPN on a Google Cloud e2-micro VM, set up with a few `gcloud` commands.

```
Your device ──encrypted UDP 51820──▶ GCP VM (WireGuard + NAT) ──▶ Internet
                                     websites see the VM's IP
```

## Architecture

```mermaid
flowchart LR
    subgraph clients["Your devices"]
        phone["📱 Phone<br/>10.8.0.2"]
        laptop["💻 Laptop<br/>10.8.0.3"]
        pc["🐧 Linux / WSL<br/>10.8.0.4"]
    end

    subgraph gcp["Google Cloud project"]
        ip["Static IP<br/>(Standard tier)"]
        fw{{"Firewall<br/>allow UDP 51820<br/>tag: wireguard"}}
        subgraph vm["e2-micro VM · Debian 12"]
            wg["wg0 (WireGuard)<br/>10.8.0.1/24 :51820"]
            nat["iptables NAT<br/>MASQUERADE → ens4"]
            helper["wg-add-client<br/>(profiles + QR)"]
        end
    end

    web(("🌐 Internet"))

    phone & laptop & pc == "encrypted tunnel<br/>UDP 51820" ==> ip
    ip --> fw --> wg
    wg -- "decrypted traffic" --> nat
    nat -- "source = static IP" --> web
    helper -. "adds [Peer]" .-> wg
```

**How a request flows**
1. A device sends traffic into its WireGuard tunnel (`AllowedIPs = 0.0.0.0/0`, so everything goes through the tunnel).
2. The packet reaches the VM's static IP on UDP 51820, which the firewall rule allows.
3. `wg0` decrypts it and checks the device's key against its `[Peer]` entry.
4. iptables NAT rewrites the source address to the VM's IP and sends the packet to the internet.
5. Replies come back the same way, encrypted, to the device.

**What the scripts do**

```mermaid
flowchart TB
    D["deploy.sh"] --> A["Reserve static IP"] --> F["Create firewall rule"] --> V["Create VM<br/>+ startup script"]
    V --> S["server-setup.sh on VM:<br/>install WireGuard, enable IP forwarding,<br/>NAT, wg-add-client"]
    S --> C["Download profiles → clients/*.conf"]
    AC["add-client.sh"] --> C
    CI["change-ip.sh"] -->|"new IP, release old,<br/>update Endpoint in profiles"| C
    X["destroy.sh"] -->|"delete VM, IPs, firewall"| Z["Nothing billed"]
```

## VPN types, and which one this is

### By purpose
| Type | What it does | Example |
|---|---|---|
| **Remote-access VPN** | One device connects to a server and uses its network or internet connection | Work-from-home VPN, **this repo** |
| **Site-to-site VPN** | Joins two whole networks, such as two offices or an office and the cloud, so they act as one | GCP Cloud VPN, AWS Site-to-Site VPN |
| **Commercial privacy VPN** | A paid service that lends you its servers' IPs | NordVPN, ProtonVPN, Mullvad |
| **Mesh / overlay VPN** | Every device connects directly to every other device, with no central server for traffic | Tailscale, ZeroTier, Nebula |
| **Self-hosted VPN** | You run the server yourself, so only you control it and its logs | **This repo**, Algo, PiVPN |

### By protocol
| Protocol | Transport | Notes |
|---|---|---|
| **WireGuard** | UDP | Modern, very fast, small codebase, current cryptography. **Used here.** |
| OpenVPN | UDP or TCP | Mature and flexible. TCP mode gets through strict firewalls but is slower. |
| IPsec / IKEv2 | UDP 500/4500 | Built into most operating systems and routers, common for site-to-site. Reconnects well on phones. |
| SSL/TLS VPN | TCP 443 | Looks like HTTPS, so it rarely gets blocked. Mostly corporate products (Cisco AnyConnect, OpenConnect). |
| L2TP/IPsec | UDP | Older and slower. Sometimes blocked because of its fixed ports. |
| SSTP | TCP 443 | Mainly a Windows protocol. |
| PPTP | TCP 1723 + GRE | **Broken encryption, do not use.** |

### What this repo sets up
- **Remote-access, self-hosted VPN:** your devices connect to *your own* GCP server. No third-party provider sees your traffic.
- **Hub-and-spoke:** one server (`10.8.0.1`) in the middle, with each device getting its own address (`10.8.0.2`, `.3`, …).
- **Full tunnel:** `AllowedIPs = 0.0.0.0/0`, so *all* IPv4 traffic goes through the VPN and websites see the server's IP. Changing this to `10.8.0.0/24` would make it a **split tunnel**, where only traffic for the VPN network goes through it.
- **WireGuard over UDP 51820:** WireGuard only supports UDP. This avoids the slowdown of running TCP inside TCP, keeps delay low, survives switching between Wi-Fi and mobile data, and lets the port stay silent to anyone without a valid key.
- **Authentication:** each device has its own key pair plus a preshared key. There are no passwords.

**What it is not:** it doesn't make you anonymous (Google knows the server is yours), and it doesn't connect your devices to each other or join networks together. It also won't get through networks that block UDP. For those, move it to port 443 or wrap it in TCP (`udp2raw`, `wstunnel`).

## Requirements
- A Google Cloud account with billing enabled (the $300 free trial is enough)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) on Linux, macOS or WSL
- The WireGuard app on each device: <https://www.wireguard.com/install/>

## 1. Install and log in to gcloud
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud auth login
```

## 2. Create a project and link billing
```bash
gcloud projects create my-vpn-$RANDOM --name=wireguard-vpn
gcloud config set project <PROJECT_ID>                 # the ID printed above
gcloud billing accounts list                           # copy the ACCOUNT_ID
gcloud billing projects link <PROJECT_ID> --billing-account=<ACCOUNT_ID>
```

## 3. Deploy
```bash
./deploy.sh                    # creates profiles for "phone" and "laptop"
./deploy.sh phone laptop pc    # or name your own devices
```
This takes about 3 minutes. The device profiles are saved to `clients/<name>.conf`.

Region: the default is `us-central1-a`, where the e2-micro VM is free. To use a region closer to you (the VM then costs about $7/month):
```bash
ZONE=asia-southeast1-a ./deploy.sh
```
Use the same `ZONE=...` with every script below.

## 4. Connect a device
| Device | How |
|---|---|
| Phone | `./add-client.sh phone`, then in the WireGuard app tap **+ → Scan from QR code** |
| Windows / macOS | WireGuard app → **Import tunnel from file** → `clients/laptop.conf` |
| Linux | `sudo apt install wireguard-tools && sudo cp clients/pc.conf /etc/wireguard/ && sudo wg-quick up pc` |

Check it works: `curl ifconfig.me` should print the VM's IP.

Give every device its own profile. Two devices using the same profile kick each other off.

## Scripts
| Script | What it does |
|---|---|
| `deploy.sh [devices...]` | Creates a fixed IP, the firewall rule (UDP 51820) and the VM, then downloads the profiles |
| `add-client.sh <name>` | Adds a device, or re-downloads an existing one, and shows its QR code |
| `change-ip.sh` | Gives the VM a new public IP, releases the old one and updates every profile |
| `destroy.sh` | Deletes the VM, its IPs and the firewall rule |
| `server-setup.sh` | Runs on the VM on first boot: installs WireGuard, NAT and the `wg-add-client` helper |
| `common.sh` | Shared settings: `PROJECT`, `ZONE`, `VM_NAME` (override with env vars) |

`change-ip.sh` cuts off the VPN while it runs. Turn the VPN off on the machine running it first (`sudo wg-quick down <name>`), then re-import or edit the profiles on your devices afterwards.

## Useful commands
```bash
gcloud compute ssh wg-vpn --zone=us-central1-a --command='sudo wg show'   # connected devices
gcloud compute instances stop  wg-vpn --zone=us-central1-a                # pause (disk + IP still billed)
gcloud compute instances start wg-vpn --zone=us-central1-a
```

## Costs (approximate)
| Item | Cost |
|---|---|
| e2-micro VM | Free in us-central1/us-west1/us-east1, about $7/month elsewhere |
| Static IPv4 | About $3/month |
| Traffic leaving the VM (Standard tier) | About $0.085/GB, which is the main cost |

Set a budget alert at **Billing → Budgets & alerts**. Free-trial credit expires after 90 days.

## Notes
- WSL: the VPN only covers Linux traffic inside WSL. Use the Windows app to cover the whole PC.
- Profiles in `clients/` contain private keys. They are git-ignored, so never share or commit them.
- Each device has its own key plus a preshared key. To revoke a device, delete its `[Peer]` block from `/etc/wireguard/wg0.conf` on the VM, then run `sudo systemctl restart wg-quick@wg0`.
