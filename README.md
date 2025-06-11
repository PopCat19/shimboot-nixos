# Shimboot - NixOS Fork
> [Shimboot](https://github.com/ading2210/shimboot) is a collection of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux distribution. It allows you to boot a full desktop Debian install on a Chromebook, without needing to unenroll it or modify the firmware.

This is my work-in-progress fork of [ading2210](https://github.com/ading2210)'s [Shimboot](https://github.com/ading2210/shimboot). The goal here is to take the original, script-based build process and rewrite it with [Nix](https://nixos.org/) to make it fully declarative and reproducible.

This is a learning project for me. I'm still new to Nix, so I'm relying on documentation and some LLM guidance to figure things out. The main idea is to replace the shell scripts with a Nix flake that can build a complete, bootable shim image from (hopefully) a single command.

### Why Nix?
*   **Reproducibility:** Anyone should be able to clone this repo, run `nix build`, and get the exact same result, regardless of what's on their machine.
*   **Atomic Builds:** Builds either succeed completely or fail cleanly, without leaving a half-broken system or temporary files everywhere.
*   **Declarative Dependencies:** Instead of scripts calling other scripts, Nix tracks the entire dependency graph, making the process easier to understand and maintain.

### Project Roadmap & Status
-   [x] **Project Scaffolding:** The project is now a Nix flake.
-   [x] **Patched `systemd`:** The `mount_nofollow` patch is working and applied via a Nix overlay.
-   [x] **Binary Cache:** A [Cachix cache](https://app.cachix.org/cache/shimboot-systemd-nixos) is live and hosts the patched `systemd`.
-   [x] **FHS Rootfs Generation:** The `rootfs` is now successfully built using `buildEnv`, creating a proper FHS directory structure.
-   [x] **Final Image Assembly:** The `build-final-image.sh` script successfully automates the entire build and assembly process.
-   [?] **Testing on Hardware:**
        -   **Status:** **shimboot menu boots**
        -   **Details:** The generated `shimboot_nixos.bin` image successfully
            boots on a `dedede` device. The custom `initramfs` runs and the
            `Shimboot OS Selector` correctly identifies the
            `nixos on /dev/sda4` partition.
        -   **Current Issue:** Selecting the `nixos` option results in a black
            screen and a reboot (likely a kernel panic). The root cause was
            identified: the `rootfs` was built with symlinks pointing to
            `/nix/store` paths that don't exist within the `rootfs` itself.
            The `init` process fails because it cannot find essential
            binaries like `/sbin/init`.
        -   **Next Steps:** Re-evaluate the `rootfs` creation process. The
            current plan is to abandon the symlink-based `buildEnv` approach
            and instead construct a `rootfs` that contains the actual files
            from the Nix store, not just pointers to them. This will likely
            involve using a different Nix function or manually copying store
            paths into the image during the build process.
-   [ ] **Declarative Artifacts (Future Goal):** The manual extraction and patching steps in `build-final-image.sh` should eventually be moved into pure, hashed Nix derivations.

### How to Build (Current WIP State)
**This isn't ready for general use!** These instructions are for developers who want to follow along.
1.  **Prerequisites:** A working Nix installation with flakes enabled, and necessary build tools (`vboot_utils`, `binwalk`, etc.) installed system-wide.
2.  **Clone this repo** (specifically the `nixos` branch).
3.  **Get the Shim:** Download the official RMA shim for your board and place it at `./data/shim.bin`.
4.  **Build the Image:** Run `sudo ./scripts/build-final-image.sh`. This will build all components and create `shimboot_nixos.bin`.

### Project Credits
- [**ading2210**](https://github.com/ading2210) for the shimboot project and its derivatives.
- Feedback and assistance from those participating in the [original discussion](https://github.com/ading2210/shimboot/discussions/335).
- [**t3.chat**](https://t3.chat/) for providing useful LLMs for guidance.
