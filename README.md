# Telegram MTProto WS Proxy for Proxmox (LXC)

Native Telegram MTProto Proxy with WebSocket stealth (via Cloudflare Workers) inside a Proxmox LXC container.

## 🚀 Quick Install

Run this command in your Proxmox VE shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/solohaims/proxmox-tg-proxy/main/install_tg_proxy.sh)"
```

## 🛠 Features (v2.1)
- **Russian Localization:** Full UI and prompts in Russian.
- **Improved UI:** Arrow-key navigation for storage and resource selection.
- **Hardened Security:** 
  - Automatically creates **Unprivileged** containers.
  - Generates a **random root password** for every installation.
  - Systemd hardening (`ProtectSystem`, `PrivateTmp`).
- **Resource Profiles:** Choose between Eco, Standard, or Performance settings.
- **Native Performance:** Python-native installation (no Docker overhead).
- **WS Stealth:** Bypasses DPI by routing traffic through Cloudflare Workers.
- **Automatic Setup:** Handles template downloading, network waiting, and service configuration.

## ☁️ Cloudflare Worker Setup
To use the **Stealth Link**, you must deploy a Worker in your Cloudflare account:

1. Create a new **Worker** in Cloudflare Dashboard.
2. Replace the code with this snippet:

```javascript
import { connect } from "cloudflare:sockets";

export default {
  async fetch(request) {
    if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
      return new Response("Expected websocket", { status: 426 });
    }
    const url = new URL(request.url);
    const dst = url.searchParams.get("dst");
    if (!dst || url.pathname !== "/apiws") {
      return new Response("Invalid request", { status: 400 });
    }
    const [client, server] = new WebSocketPair();
    server.accept();
    let tcpSocket;
    server.addEventListener("message", async (event) => {
      if (!tcpSocket) {
        tcpSocket = connect({ hostname: dst, port: 443 });
        tcpSocket.readable.pipeTo(new WritableStream({
          write(chunk) { server.send(chunk); },
          close() { server.close(); },
          abort() { server.close(); }
        }));
      }
      const writer = tcpSocket.writable.getWriter();
      await writer.write(event.data);
      writer.releaseLock();
    });
    return new Response(null, { status: 101, webSocket: client });
  }
};
```
3. Save and deploy. Use your `.workers.dev` domain during the script installation.

## 📄 Credits
- Proxy core: [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy)
- Script inspired by [Proxmox VE Helper Scripts](https://tteck.github.io/Proxmox/)
