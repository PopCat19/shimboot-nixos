# Shimboot - NixOS Fork
> [Shimboot](https://github.com/ading2210/shimboot) is a collection of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux distribution. It allows you to boot a full desktop Debian install on a Chromebook, without needing to unenroll it or modify the firmware.

This is my work-in-progress fork of [ading2210](https://github.com/ading2210)'s [Shimboot](https://github.com/ading2210/shimboot). The goal here is to take the original, script-based build process and rewrite it with [Nix](https://nixos.org/) to make it fully declarative and reproducible.

This is a learning project for me. I'm still new to Nix, so I'm relying on documentation and some LLM guidance to figure things out. The main idea is to replace the shell scripts with a Nix flake that can build a complete, bootable shim image from (hopefully) a single command.

### Why Nix?
*   **Reproducibility:** Anyone should be able to clone this repo, run `nix build`, and get the exact same result, regardless of what's on their machine.
*   **Atomic Builds:** Builds either succeed completely or fail cleanly, without leaving a half-broken system or temporary files everywhere.
*   **Declarative Dependencies:** Instead of scripts calling other scripts, Nix tracks the entire dependency graph, making the process easier to understand and maintain.

### Project Roadmap & Status (initial roadmap devised with assistance from LLMs; subject to change)
-   [x] **Project Scaffolding:** The project is now a Nix flake. The old scripts have been archived for reference, and declarative logic lives in the `nix/` directory.
-   [x] **Patched `systemd`:** The `mount_nofollow` patch was the first big hurdle. The original patch from [ading2210/chromeos-systemd](https://github.com/ading2210/chromeos-systemd) didn't work on latest `systemd`, so I had to create a new diff with the [systemd repo](https://github.com/systemd/systemd). This is now applied automatically via a [Nix overlay](nix/overlay.nix).
-   [x] **Binary Cache:** To avoid long compile times, I've set up a [Cachix cache](https://app.cachix.org/cache/shimboot-systemd-nixos). This hosts the patched `systemd` and other dependencies. I haven't fully tested it with others yet, but it should work.
    -   **Cache URL:** `https://shimboot-systemd-nixos.cachix.org`
    -   **Public Key:** `shimboot-systemd-nixos.cachix.org-1:vCWmEtJq7hA2UOLN0s3njnGs9/EuX06kD7qOJMo2kAA=`
-   [ ] **FHS Rootfs Generation:**
    -   **Status:** In Progress.
    -   **Details:** I'm trying to use `buildFHSEnv` to create a rootfs directory that looks like a standard Linux system. While the initial builds succeeded, the output isn't a directory structure like `/bin`, `/etc`, etc. I'm skeptical if is the right tool, so the next step is to investigate the output and possibly try a tool like `buildEnv` that just produces a directory.
-   [ ] **Kernel & Initramfs Extraction:**
    -   **Status:** Not Started (in Nix).
    -   **Details:** I've manually extracted the `kernel.bin` from the shim (currently data/kernel.bin), but the goal is to have a Nix derivation do this automatically and reliably. The `initramfs` extraction is also a challenge due to my current unfamiliarity with the existing shimboot scripts.
-   [ ] **Final Image Assembly:**
    -   **Status:** Not Started.
    -   **Details:** A simplified (untested) `create-image.sh` script exists, but it's waiting for the declarative artifacts (rootfs, kernel, initramfs) to be ready.

### How to Build (Current WIP State)
**This isn't ready for general use!** These instructions are for developers who want to follow along.
1.  **Prerequisites:** You need a working Nix installation with flakes enabled.
2.  **Clone this repo** (specifically the `nixos` branch).
3.  **Get the Shim:** Download the [official RMA shim](https://chrome100.dev/) for your board (I'm using `dedede`), then rename and place it at `./data/shim.bin`. (bin may already exist; it's a `dedede` shim. replace if needed)
4.  **Build the Rootfs:** Run `nix build .#` in `shimboot-nixos`. This should succeed (using the cache) and create a `./result` symlink. **Note that this `result` is currently not the final rootfs directory.**

### Project Credits
[**ading2210**](https://github.com/ading2210) for the shimboot project and its derivatives: [ading2210/shimboot](https://github.com/ading2210/shimboot) / [ading2210/chromeos-systemd](https://github.com/ading2210/chromeos-systemd)
Feedback and assistance from those participating in [NixOS shimboot with systemd patches #335](https://github.com/ading2210/shimboot/discussions/335) discussion.
[**t3.chat**](https://t3.chat/) for providing useful LLMs for guidance.
