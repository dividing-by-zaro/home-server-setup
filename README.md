# Turning a pandemic-era PC into a home server with a private LLM & self-hosting

This file documents the steps I took to set up a home server.

Three main goals:
- Have 100% private & end-to-end encrypted chats with a local LLM running on my own hardware, accessible from anywhere
- Host backends & databases for side projects & sideloaded apps (e.g. period tracker, workout tracker)
- Don't spend a lot of money doing any of this

After realizing I hadn't booted up my windows machine in about 6 months, I decided to give homelabbing a go with the lowest cost options available to me.

Claude optimistically suggested this setup might take me 90 minutes. It took me about a day, more or less.

## Table of contents

- [Requirements](#requirements)
- [Questions I anticipate](#questions-i-anticipate)
- [Hardware](#hardware)

**Setting up the server**

1. [BIOS Configuration](#1-bios-configuration)
2. [Create Bootable USB](#2-create-bootable-usb)
3. [Install Ubuntu Server](#3-install-ubuntu-server)
4. [SSH In and Mount the 1TB Drive](#4-ssh-in-and-mount-the-1tb-drive)

**Self-hosting with Coolify**

5. [Set up Coolify & deploy a project](#5-set-up-coolify--deploy-a-project)
6. [Reserve Static LAN IP](#6-reserve-static-lan-ip)

**Connecting a domain & networking**

7. [Buy a Domain](#7-buy-a-domain)
8. [Cloudflare Tunnel](#8-cloudflare-tunnel)
9. [Cloudflare Access (Auth Gate)](#9-cloudflare-access-auth-gate)

**Setting up the local LLM**

10. [Set up llama.cpp](#10-set-up-llamacpp)
11. [Download a Model](#11-download-a-model)
12. [Run llama-server](#12-run-llama-server)
13. [Run llama-server as a Persistent Service](#13-run-llama-server-as-a-persistent-service)

**Adding end-to-end encryption**

14. [Install Tailscale](#14-install-tailscale)

**Migrating off Railway**

15. [Migrating a Database from Railway](#15-migrating-a-database-from-railway)

## Requirements

Money I spent:
- $13.99 on an ethernet cable
- $20 to rent the domain `zaro.host` for a year (though this is purely cosmetic)

Materials I used that I already had:
- The PC I used for this build cost $1145 in 2020
- A 500gb USB drive of my wife's (8gb would have been just fine)
- Home internet (we pay $50/month for 50 Mbps up/down - yet to be determined how this fares)

Time spent:
- About 6-8 hours actively working (running shell commands, chatting with Claude, running to the hardware store, etc.)
- About 24 hours in total from when I first booted up my PC (I waited overnight for DNS propagation)
- A couple of hours to write up this doc

Logins needed:
- Coolify (for self-hosting)
- Cloudflare (for connecting up your domain name to coolify-hosted projects & hiding your home IP)
- Tailscale (if you want end-to-end encryption between devices)
- Google (or another SSO for Tailscale)
- Hugging Face (to download models)

AI accounts I used:
- Claude Max to orchestrate the build & troubleshoot (Claude is my main man) ($100/month)
- ChatGPT Pro for open weights model comparison (I find it better for search) ($20/month)

Downloads:
- [Ubuntu Server](https://ubuntu.com/download/server)
- [Docker](https://get.docker.com)
- [Coolify](https://coolify.io)
- [cloudflared](https://pkg.cloudflare.com)
- [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) (via `apt`)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
- [Hugging Face CLI](https://huggingface.co/docs/huggingface_hub/guides/cli) (via `pip`)
- [Gemma 2 9B GGUF](https://huggingface.co/bartowski/gemma-2-9b-it-GGUF)
- [Qwen 2.5 7B GGUF](https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF)
- [Tailscale](https://tailscale.com/download)

## Questions I anticipate

How does the local LLM compare to ChatGPT or Claude?
> So far I've been using Gemma 2 9B (4-bit quantized). The intelligence is okay, the speed is slower (about 10 tokens/second), and the context window I'm able to support on this GPU is very small (only about 2k tokens). General "seeking information" type questions work great. I plan to compare many models for this use case.

Why not use Ollama?
> llama.cpp recently introduced a native web UI that looks super nice, in my opinion. I didn't want to have to set up OpenWebUI. I'm very happy with llama.cpp and it was dead simple to set up.

Is Coolify cheaper than hosting on Railway?
> It's similar - for my use case at least. Rough estimates of electricity usage put me at around $10 a month, assuming constant idle. That doesn't factor in LLM inference, nor any increased data usage (my ISP has a monthly data cap). I plan to monitor this.

Is Coolify easier to use than Railway?
> No. Self-hosting makes things harder - but more rewarding, depending on your values. Coolify has definitely taken some getting used to, though I think it's more a case of things being moved around in the UI than actually having bad functionality. So far, I think Railway's interface makes it easier to connect up different services, and the way Coolify's proxy works is less intuitive to me.

How loud is the server?
> I think it's pretty quiet, but it's definitely there. I don't notice a big difference when LLM inference is running - maybe it's around 20% louder. We keep it in the living room by the router so it isn't as bothersome.

What happens when the power/internet goes out?
> The server breaks, of course. :crying: I turned on restore on AC power loss, so it will restart when the power comes back on, and the internet will reconnect when it comes back on.

## Hardware

I used a prebuilt PC I originally bought from Ironside computers in 2020. It's gotten a fair amount of use but still works great. The main deficiency is the tiny C drive. Of course a bigger GPU might be nice for running bigger models. With a 3090, you could comfortably run 30-36B models, which is a big step up in intelligence. And, the bigger context window would be nice (more on this later).

Specs:
- **CPU**: Intel Core i5-9400F (6 cores, no integrated graphics — the "F" matters)
- **RAM**: 32GB DDR4
- **Storage**: 120GB SSD (OS) + 1TB HDD (data)
- **GPU**: GTX 1660 Super 6GB
- **PSU**: 500W 80 Plus
- **Network**: Internal Wireless AC (motherboard had an RJ45 ethernet port despite it not being listed in the build sheet)
- **Motherboard**: H310 chipset

Installing Ubuntu server wipes whatever drive you put it on, so I backed everything up to Google Drive before starting. Not the most ideal solution, but I didn't have too many files worth saving. It took about an hour to fully upload.

## 1. BIOS Configuration

Before installing Ubuntu server, there were a couple of settings that needed to be changed on the hardware.

I had booted into the BIOS before but couldn't remember how. I failed one attempt because the bluetooth keyboard I use apparently doesn't work for this sort of thing.

Holding shift during shutdown & restarting with the "troubleshooting" option got me there.

I updated:

- **Restore on AC Power Loss** → Power On (found under Power Management or Advanced > APM Configuration)
- **Boot order** → UEFI: USB Key first (temporary, for OS installation)

I had hoped to update Wake-on-LAN for remote startup, but couldn't find the setting.

## 2. Create Bootable USB

Next, I installed the Ubuntu server on the machine. This was probably the hardest step (it took about 6 or 7 tries to get it right).

I had a few false starts here, mostly because this computer's CPU doesn't have integrated graphics, so plugging in my monitor gave an error message that the display resolution wasn't supported.

A few things I tried:

### Just SSH into the machine!

Wait, but my PC doesn't have integrated WiFi in the CPU ... 

**Solution:** Run to Ace Hardware to get an ethernet cable (yes, Ace Hardware sells data cables).

### Just SSH into the machine, now that it's connected via ethernet!

Wait, but Ubuntu generates a random password for the `installer` user that's ... displayed on the screen.

This took a lot of troubleshooting. Ultimately, I ended up modifying the `.iso` file to include my SSH key as well as a known password for the `installer` user. This was non-trivial and took several attempts. Several times I tried to SSH in only to get permission denied, and once I was able to log into the `root` user but not `installer`.

**Solution:** I had Claude Code modify the `.iso` file by giving it [the entire post & comments from this forum thread](https://discourse.ubuntu.com/t/how-can-i-install-ubuntu-server-on-a-headless-machine-with-ssh-access-only/62410), which eventually got us on the right track. (I originally provided only the solution, which led to... the same commenting issue the OP ran into later.)

### So, to summarize what actually worked:

- Download [Ubuntu Server 24.04 LTS](https://ubuntu.com/download/server)
- Have Claude Code modify the `.iso` file using [the entire post & comments from this forum thread](https://discourse.ubuntu.com/t/how-can-i-install-ubuntu-server-on-a-headless-machine-with-ssh-access-only/62410) as a reference
- Use the terminal to locate & unmount the drive, then flash the OS onto the drive using `dd`

I ran into an issue here where `~` wasn't properly expanding with `sudo`. I had to use the full path:

```bash
diskutil list                    # identify your USB drive
diskutil unmountDisk /dev/diskN  # replace N with your drive number
sudo dd if=/Users/$(whoami)/Downloads/ubuntu-24.04-live-server-amd64.iso of=/dev/rdiskN bs=1m status=progress
diskutil eject /dev/diskN
```
Plug in the USB drive, start up the computer, and wait a few minutes for it to get an IP address from your router. Once you can see the client in your router backend, you can SSH into it to complete the installation:

```bash
ssh installer@SERVER_IP
```

## 3. Install Ubuntu Server

With that nightmare over, it was finally time to install the server. These steps are well-documented and straightforward. Installation only took a couple of minutes.

1. Select "Install Ubuntu Server"
2. Choose language, keyboard, network (DHCP is fine)
3. At disk selection: choose the 120GB SSD, select "Use entire disk" (wipes Windows)
4. Create your username and password
5. Enable OpenSSH server when prompted
6. Complete installation, reboot, remove USB

DO NOT forget to remove the USB, because you won't realize why you're not able to SSH into the new user you created ... I actually had to go downstairs **again** to do this, smh.

## 4. SSH In and Mount the 1TB Drive

Thank god, now you can properly SSH into the thing, allowing you to do everything else from the comfort of your couch.

From my Macbook:

```bash
ssh youruser@SERVER_IP
```

Then I used a few commands to mount the 1TB drive:

```bash
lsblk  # identify the 1TB drive (e.g., /dev/sdb)

# Wipe existing Windows partitions
sudo wipefs -a /dev/sdb
sudo parted /dev/sdb mklabel gpt
sudo parted /dev/sdb mkpart primary ext4 0% 100%

# Format
sudo mkfs.ext4 /dev/sdb1

# Mount
sudo mkdir /mnt/data
sudo mount /dev/sdb1 /mnt/data

# Persist across reboots
echo '/dev/sdb1 /mnt/data ext4 defaults 0 2' | sudo tee -a /etc/fstab
```

Verify: `df -h /mnt/data`

## 5. Set up Coolify & deploy a project

The whole goal here is to not need Railway anymore - to be able to host my own app backends & databases. Coolify is a self-hosted Railway-like platform as a service that can deploy from a git repo. Docker is needed to run Coolify.

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
logout
```

Log back in, verify: `docker run hello-world`

Then Coolify:

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

Access the dashboard from another machine: `http://SERVER_IP:8000`. Create your admin account on first load.

For whatever reason, the IPs Coolify prints after installation are internal Docker network interfaces. I needed to use the LAN IP instead.

### Point Coolify data to the 1TB drive

Edit `/etc/coolify/.env`, set `DATA_DIR=/mnt/data/coolify`:

```bash
sudo systemctl stop coolify
sudo mkdir -p /mnt/data/coolify
sudo rsync -a /data/coolify/ /mnt/data/coolify/
sudo nano /etc/coolify/.env  # change DATA_DIR
sudo systemctl start coolify
```

### Deploying an app

Deploying was a small learning curve, as the interface differs from Railway, which I'm used to.

I chose a simple side project to deploy - [Through Their Eyes](https://github.com/dividing-by-zaro/through-their-eyes). Not needing environment variables or a db kept things simple.

1. In Coolify: New Project → Add Resource → select Git provider
2. Point at a repo, set environment variables, assign a domain
3. Click Deploy

I used Claude Code to generate a Dockerfile and Caddyfile for this project, since I previously was using Railway's Nixpacks (in Coolify, I have been building from Dockerfile).

I originally deployed from a public GitHub repo (to avoid having to set up the GitHub app), but that didn't appear to be auto-redeploying on commits to main. Later, I set up the GitHub app and can confirm this feature works well!

Assigning a domain also wasn't quite as straightforward as I originally thought. Coolify creates a random public url that ends in `sslip.io`, but I wasn't able to access the deployed site from there on my Macbook. Claude said the issue was something to do with the Coolify proxy. I got several different warnings & errors at this step. I proceeded with setting up Cloudflare rather than troubleshooting, since I planned to use my own domain anyway.

There's a lot of complexity I haven't yet explored with Coolify's ports & proxying, though I plan to. My approach was just to get something working, then come back and figure out the details later.

It is important to know that Coolify's proxy runs on port 80 and routes to app containers by hostname. App containers expose ports internally (e.g., `3000/tcp`) but don't bind to the host.

## 6. Reserve Static LAN IP

To preserve the server's local IP across reboots, I reserved its IP. This was very easy to do in the router's admin page (I was able to just select it from a drop-down).

My router brand has an FAQ page about this step: [https://www.tp-link.com/us/support/faq/182/](https://www.tp-link.com/us/support/faq/182/)

## 7. Buy a Domain

This is optional and purely cosmetic, but I like having all my projects hosted together, and I think domain names are relatively cheap for how professional they look when sharing your projects.

I ended up paying $20 for a year of `zaro.host`. 

I already own `isabelzaro.com`, but I was worried about interrupting email service if records didn't transfer correctly when moving DNS to Cloudflare. I use my email for important stuff, so I thought it best not to introduce potential complications.

## 8. Cloudflare Tunnel

Cloudflare has a generous free plan, and tunnels are highly recommended to expose services to the internet without revealing your home IP or opening router ports. It also helps with DDoS protection (as if my projects are getting any traffic at all, lol). And, as a bonus, it's really easy to add subdomains (like `chat.zaro.host`).

The "big" downside is that you've now got a man in the middle, and Cloudflare will see your data in plaintext at some point during proxying. It really depends what kind of data you're moving around. For the ultraprivacy of end-to-end encryption, you'll need Tailscale (detailed later in this post).


### Install cloudflared

Use **64-bit** and **Debian** for the OS.

```bash
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt-get update && sudo apt-get install cloudflared
```

### Create a tunnel

1. Add your domain to [Cloudflare](https://dash.cloudflare.com)
2. Go to Zero Trust → Networks → Tunnels → Create a tunnel
3. Cloudflare gives you an install command with a token — run it on your server
4. Map subdomains under the **"Published application routes"** tab

As I mentioned earlier, Coolify's proxy uses port 80, so all your Coolify-hosted projects can direct to `localhost` at port 80.

When adding routes, I set Service type to **HTTP** (not HTTPS) — apparently the tunnel handles encryption, so the internal connection stays HTTP.

Claude suggested using a wildcard shortcut to Map `*.yourdomain.com` → `http://localhost:80`, which means you only need to touch Cloudflare when adding a non-Coolify service, but I wasn't sure how this would work, so I didn't set it up.

At this point, adding the domain in Coolify worked, and I was able to access my app from my Macbook (you can too, at through-their-eyes.zaro.host!).

### Route examples

| Subdomain | Service |
|---|---|
| `coolify.yourdomain.com` | `http://localhost:8000` |
| `app.yourdomain.com` | `http://localhost:80` |
| `chat.yourdomain.com` | `http://localhost:8081` |

### Coolify networking notes

- **The domain field needs the full URL with scheme**, e.g. `http://through-their-eyes.zaro.host` — not just the hostname

## 9. Cloudflare Access (Auth Gate)

Now that I had an app deployed on my home server, I wanted to set up LLM chat.

To my delight, llama.cpp recently introduced a web UI that is easily accessible at port 8081. However, since I want the service to be accessible from anywhere (`chat.zaro.host`), of course anyone can hit that endpoint. Setting up auth is generally annoying, but Claude mentioned Cloudflare has its own auth gate that puts a login screen in front of any subdomain, which is awesome.

1. Zero Trust → Access → Applications → Add application
2. **Type**: Self-hosted
3. **Application domain**: whatever domain you want here
4. Create a new policy - I used action Allow, type email, and added all my emails plus my wife's emails. If other users hit this endpoint, they'll be able to enter their email, but they will not be sent a code to log in and they won't reach the server (I tested this myself)
5. Make sure to go back to add application and add the policy to complete everything.

Add this to any subdomain you want protected (Coolify dashboard, LLM web UI, etc.).

llama.cpp also has a built in `--api-key` flag. I considered this option, but that would mean building some type of frontend that can accept an api key, and that just seemed like a hassle comparatively.

At this point, you're ready to set up llama.cpp on the server.

## 10. Set up llama.cpp

Claude told me to install NVIDIA drivers at this step, but they had already been installed as part of the ubuntu server setup earlier.

First, you'll need the cuda toolkit:

```bash
sudo apt install -y nvidia-cuda-toolkit
```

Then llama.cpp itself:

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_CUDA=ON
cmake --build build --config Release -j$(nproc)
```

## 11. Download a Model

It was difficult to decide which model to go with. I initially planned on using Mistral 7B. Some sources say it's smart for its size, others say it's the dumbest model out there. It was difficult to get good information here.

I eventually decided on Gemma 2 - my plan was to test out a bunch of models and see how they perform. Obviously we're not going to be doing any high-powered stuff with this model, but rather using it purely when privacy is desired.

First, I had to install pip:

```bash
sudo apt install -y python3-pip
```

Then the Hugging Face CLI:

```bash
pip install -U "huggingface_hub[cli]" --break-system-packages
```

Claude repeatedly told me to use the alias `huggingface-cli`, which has apparently been deprecated in favor of `hf`. It also gave me the wrong login command. Context7 would've helped, but I was using the desktop app and figured this out pretty easily ("not found" commands are pretty descriptive).

Create a models directory:

```bash
sudo mkdir -p /mnt/data/models
sudo chown $USER:$USER /mnt/data/models
```

Log in & create a read-access token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens), then use the token to login on the server:

```bash
hf auth login --token YOUR_TOKEN
```

### Model selection for 6GB VRAM (GTX 1660 Super)

The model file + KV cache + compute buffers all need to fit in the GPU's VRAM. According to a random source I found online, a 6GB GPU can comfortably run ~4–5GB model files.

I plan to try some other models later, but what I understand matters is to just keep an eye on the model's size, make sure it's a GGUF, and make sure it's an "instruct" model (not a text completer).

**Gemma 2 9B (Q4_K_S — 5.48GB):**

```bash
hf download bartowski/gemma-2-9b-it-GGUF \
  --include "gemma-2-9b-it-Q4_K_S.gguf" \
  --local-dir /mnt/data/models/
```

Claude claimed using Gemma would require accepting a license, but I didn't have to. Gemma also doesn't support system prompts.

**Qwen 2.5 7B (Q5_K_M — 5.44GB):**

```bash
hf download bartowski/Qwen2.5-7B-Instruct-GGUF \
  --include "Qwen2.5-7B-Instruct-Q5_K_M.gguf" \
  --local-dir /mnt/data/models/
```

Apparently, you can keep multiple GGUFs on disk and swap by changing the `--model` path.

## 12. Run llama-server

This took a couple of goes due to out of memory issues.

The working config ended up being:

```bash
./build/bin/llama-server \
  --model /mnt/data/models/gemma-2-9b-it-Q4_K_S.gguf \
  --host 0.0.0.0 \
  --port 8081 \
  --n-gpu-layers 25 \
  --parallel 1 \
  --ctx-size 2048
```

This takes a few minutes to run.

Key settings to change to fit the model:

- `--n-gpu-layers N` — offload N layers to GPU (lower = more on CPU, less VRAM used)
- `--parallel 1` — single request at a time (default 4, each needs its own KV cache)
- `--ctx-size 2048` — reduce context window (default 8192 uses much more VRAM)

`--host 0.0.0.0` is required — without it, the server only listens on localhost and is inaccessible from other machines or Cloudflare Tunnel.

If you get "cudaMalloc failed: out of memory" or segfaults, reduce `--n-gpu-layers`. For Gemma 2 9B (42 layers), 25 on GPU worked. Full offload (`99`) did not.

At this point, the site was up and running! It was so exciting to access from `chat.zaro.host`, get the login prompt from Cloudflare, and be able to chat with an LLM running at home. 

Keep in mind, everyone who logs in shares the same chat history. So, my wife and I see each other's chats here.

So far, I've been getting about 10 tokens/second when using this model, and the intelligence seems fine for everyday tasks. I do plan to test a few head-to-head with my own prompts at some point, but I'm also hoping more intelligent smaller models continue to come out.

The small context window is definitely a limiter. I might also try the 3-bit quantized version for faster inference.

You really don't realize how demanding these things are to run until you try to fit them on what I'd consider a decent home computer. This is like, a tiny model with like, a tiny context window, and it still doesn't fit on a GPU that runs Elden Ring handily.

## 13. Run llama-server as a Persistent Service

You don't want to have to SSH into the server to start llama.cpp every time you want to chat. To keep llama.cpp running (and have it start on boot + restart on crash), you can create a systemd service.

```bash
sudo nano /etc/systemd/system/llama-server.service
```

```ini
[Unit]
Description=llama.cpp server
After=network.target

[Service]
Type=simple
User=youruser
ExecStart=/home/youruser/llama.cpp/build/bin/llama-server \
  --model /mnt/data/models/gemma-2-9b-it-Q4_K_S.gguf \
  --host 0.0.0.0 \
  --port 8081 \
  --n-gpu-layers 25 \
  --parallel 1 \
  --ctx-size 2048
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Check with `cat` (nano always freaks me out, I never know if it's saved or not).

```bash
sudo systemctl daemon-reload
sudo systemctl enable llama-server
sudo systemctl start llama-server
```

To swap models, edit the `--model` path in the service file and `sudo systemctl daemon-reload && sudo systemctl restart llama-server`.

## 14. Install Tailscale

As I mentioned earlier, the Cloudflare + llama.cpp setup isn't technically private. While Cloudflare has a good reputation for data privacy, and states they don't store or view your data (aside from logging anonymized metrics) - it's the same trust model as something like Vercel or Railway.

For actual privacy, I wanted an end-to-end encrypted connection so that no intermediary can read the traffic.

As ChatGPT 3.5 would say, that's where Tailscale comes in.

Tailscale creates a private mesh VPN using WireGuard. SSH into your server from anywhere, and access services with full end-to-end encryption.

The "big" tradeoff with tailscale is that you can't bring your own hostname. That ultimately makes sense, since you need to hook up each individual device to even access the server, contradicting the main need for a publicly accessible url.

Tailscale still gives you one anyway - it's just not custom. Still, for cosmetic purposes, I like a nice hostname.

### Create a tailscale account

You'll need some kind of SSO - they don't do auth themselves. I used Google.

### On the server

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
sudo systemctl enable tailscaled  # start on boot
```

Follow the auth link to connect to your Tailscale account.

Tailscale assigns each device a public 100.x.y.z IP.

Find your server's Tailscale IP:

```bash
tailscale ip -4  # run on the server, returns 100.x.x.x
```

From any Tailscale-connected device:

```bash
ssh youruser@100.x.x.x                       # raw IP
ssh youruser@device-name                      # MagicDNS short name
ssh youruser@device-name.tailnet-name.ts.net   # full MagicDNS FQDN
```

I call my server `pickle-jar`, so once all my devices were set up with Tailscale, I was able to access the llama.cpp UI with `http://pickle-jar:8081`.

### On your laptop/phone

Install Tailscale from [tailscale.com/download](https://tailscale.com/download). Only devices logged into your Tailscale account can reach the server's Tailscale IP — to everyone else, it doesn't exist.

### Three access methods for llama.cpp compared

| Method | From where | Encryption | Intermediary |
|---|---|---|---|
| `192.168.0.11:PORT` | Home LAN only | None | None |
| `chat.yourdomain.com` | Anywhere, any device | HTTPS (Cloudflare terminates) | Cloudflare sees traffic |
| `pickle-jar:PORT` via Tailscale | Anywhere, Tailscale devices only | WireGuard E2E | None — fully private |

The `http://` in Tailscale URLs doesn't mean unencrypted — WireGuard encrypts at the transport layer before traffic leaves your device.

My plan is to use the Cloudflare URL (`chat.zaro.host`) when I need access from a device without Tailscale (library computer, while traveling), and use Tailscale for full privacy on my own devices.

At this point, the LLM chat app was fully set up - running end-to-end encryption from my and my wife's devices to the server, where the LLM runs locally on our own hardware.

The high from setting up this thing was intense. One of the biggest drawbacks of LLMs is their privacy. I'm no stranger to pouring my heart out to Claude on some personal problem or another and asking its opinion. Some may find that stupid, some may find it quaint. I'm certainly not the only one. I don't think Gemma will replace Claude's often sage wisdom, but I've used it several times so far only today for personal questions that otherwise would've been probably logged permanently into ChatGPT.

## 15. Migrating a Database from Railway

This step is still in progress, due to how annoying it actually is. While working on migrating a like 75-record postgres db I started to get extremely frustrated with Railway for not allowing a simple one-click download or SOMETHING to get your data off their platform. I'm sure it's intentional.

In any case, now that I had set up a simple frontend app, I wanted to work on setting up some of my more complex apps. I use a period tracker iOS app I built myself, which currently uses a backend & db in Railway.

### Export

The basic way to do this is with `pg_dump`, but god has this been frustrating. The proxying Railway makes establishing the correct `DATABASE_PUBLIC_URL` super annoying.

Railway's Postgres public networking exposes HTTP by default, which doesn't work for `pg_dump`. You need to add a **TCP Proxy** in the database's Networking settings — this gives you a usable host and port.

Find the full connection string in Railway's Variables tab (`DATABASE_PUBLIC_URL` or assemble from individual vars). The public port is often a random high number, not 5432.

```bash
pg_dump "postgresql://USER:PASS@HOST:PORT/DBNAME" > railway_backup.sql
```

I have no idea when I even installed postgres on this machine, but it was apparently a long time ago, since I had to update it.

```bash
brew install postgresql@17
```

### Import into Coolify Postgres

This is the point I'm at now, since I want to use Tailscale to end-to-end encrypt my personal data, alongside storing it on my own server. That requires updating the backend with a new Dockerfile, setting it up in Coolify, seeding the database, connecting the backend to the database, and updating the backend url in the app (plus putting it back on my iPhone again with the new version).

### Issues I've encountered so far

- **`Can't load plugin: sqlalchemy.dialects:postgres`** — Change `postgres://` to `postgresql://` in your DATABASE_URL. SQLAlchemy requires the full scheme. For async: `postgresql+asyncpg://`.
- **`Temporary failure in name resolution`** — Your DATABASE_URL still points at Railway's hostname. Update it to the Coolify Postgres container name (e.g., `postgresql+asyncpg://postgres:PASS@CONTAINER_NAME:5432/mydb`). Containers in the same Coolify project share a Docker network.
