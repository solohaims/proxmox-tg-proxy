# Telegram MTProto WS Proxy for Proxmox (LXC)

[English](#english) | [Русский](#русский)

---

<a name="english"></a>
## English

Native Telegram MTProto Proxy with WebSocket stealth (via Cloudflare Workers) inside a Proxmox LXC container.

### 🚀 Quick Install

Run this command in your Proxmox VE shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/solohaims/proxmox-tg-proxy/main/install_tg_proxy.sh)"
```

### 🛠 Features (v2.1)
- **Russian Localization:** Full UI and prompts in Russian.
- **Improved UI:** Arrow-key navigation for storage and resource selection.
- **Hardened Security:** 
  - Automatically creates **Unprivileged** containers.
  - Generates a **random root password** for every installation.
  - Systemd hardening (`ProtectSystem`, `PrivateTmp`).
- **Resource Profiles:** Choose between Eco, Standard, or Performance settings.
- **Clean Installation:** Automatically removes build dependencies and caches to save space.
- **WS Stealth:** Bypasses DPI by routing traffic through Cloudflare Workers.
- **Automatic Setup:** Handles template downloading, network waiting, and service configuration.

### ☁️ Cloudflare Worker Setup
To use the **Stealth Link**, you must deploy a Worker in your Cloudflare account:

1. Create a new **Worker** in Cloudflare Dashboard.
2. Replace the code with the snippet provided in the [Cloudflare Code](#cloudflare-code) section below.
3. Save and deploy. Use your `.workers.dev` domain during the script installation.

---

<a name="русский"></a>
## Русский

Нативный Telegram MTProto прокси с маскировкой WebSocket (через Cloudflare Workers) внутри контейнера Proxmox LXC.

### 🚀 Быстрая установка

Запустите эту команду в консоли (shell) вашего Proxmox:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/solohaims/proxmox-tg-proxy/main/install_tg_proxy.sh)"
```

### 🛠 Особенности (v2.1)
- **Русская локализация:** Весь интерфейс и подсказки на русском языке.
- **Улучшенный UI:** Выбор хранилища и ресурсов с помощью стрелок на клавиатуре.
- **Повышенная безопасность:** 
  - Автоматическое создание **непривилегированных** (Unprivileged) контейнеров.
  - Генерация **случайного пароля root** для каждой установки.
  - Защита сервиса через Systemd (`ProtectSystem`, `PrivateTmp`).
- **Профили ресурсов:** Выбор между Эконом, Стандарт или Производительным режимами.
- **Чистая установка:** Автоматическое удаление мусора и временных зависимостей после сборки.
- **WS Stealth:** Обход блокировок DPI через Cloudflare Workers.
- **Автоматизация:** Сам качает шаблоны, ждет сеть и настраивает автозапуск.

### 🏗 Архитектура
- **Сборка из исходников:** Скрипт клонирует официальный репозиторий [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) и компилирует библиотеки шифрования (`cryptography`) локально. Это гарантирует прозрачность и безопасность.
- **Минимальные задержки:** Работает как нативный сервис systemd внутри LXC (без накладных расходов Docker).
- **Изоляция:** Использует виртуальное окружение Python (venv) для чистоты системы.

### ☁️ Настройка Cloudflare Worker
Чтобы использовать **Stealth-ссылку**, вам нужно развернуть Worker в вашем аккаунте Cloudflare:

1. Создайте новый **Worker** в панели управления Cloudflare.
2. Замените его код на фрагмент из раздела [Cloudflare Code](#cloudflare-code).
3. Сохраните и разверните (Deploy). Используйте ваш домен `.workers.dev` при запуске скрипта.

---

<a name="cloudflare-code"></a>
### 🛠 Cloudflare Code (Common)

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
      const writer = tcpSocket.writable.writable.getWriter();
      await writer.write(event.data);
      writer.releaseLock();
    });
    return new Response(null, { status: 101, webSocket: client });
  }
};
```

## 📄 Credits
- Proxy core: [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy)
- Script inspired by [Proxmox VE Helper Scripts](https://tteck.github.io/Proxmox/)
