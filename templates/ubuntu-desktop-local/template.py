from e2b import Template, wait_for_url


def make_template():
    """
    Create Ubuntu Desktop template with GNOME and VNC support
    """
    template = (
        Template()
        .from_image("ubuntu:22.04")
        .set_user("root")
        .set_workdir("/root")
        .set_envs({
            "DEBIAN_FRONTEND": "noninteractive",
            "TZ": "UTC",
            "DISPLAY": ":0",
        })
    )

    # Install system base packages
    template = template.apt_install([
        "systemd",
        "systemd-sysv",
        "dbus",
        "dbus-x11",
        "sudo",
        "curl",
        "wget",
        "git",
        "net-tools",
    ])

    # Install Ubuntu Desktop (GNOME)
    template = template.apt_install([
        "ubuntu-desktop",
    ])

    # Install VNC and remote access tools
    template = template.apt_install([
        "x11vnc",
        "novnc",
        "websockify",
        "python3-websockify",
    ])

    # Configure GDM (GNOME Display Manager) for auto-login
    template = template.run_cmd([
        "mkdir -p /etc/gdm3",
        "echo '[daemon]' > /etc/gdm3/custom.conf",
        "echo 'AutomaticLoginEnable=true' >> /etc/gdm3/custom.conf",
        "echo 'AutomaticLogin=root' >> /etc/gdm3/custom.conf",
    ])

    # Create VNC password
    template = template.run_cmd([
        "mkdir -p /root/.vnc",
        "x11vnc -storepasswd e2bdesktop /root/.vnc/passwd",
    ])

    # Copy startup script
    template = template.copy("start-desktop.sh", "/root/.desktop/start-desktop.sh")
    template = template.run_cmd("chmod +x /root/.desktop/start-desktop.sh")

    # Set startup command
    return template.set_start_cmd(
        "/root/.desktop/start-desktop.sh",
        wait_for_url("http://localhost:6080")
    )
