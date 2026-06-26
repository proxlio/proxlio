# Proxlio install demo — generated with VHS (https://github.com/charmbracelet/vhs)
#
# Install VHS:
#   brew install vhs        # macOS
#   snap install vhs        # Linux (snap)
#   go install github.com/charmbracelet/vhs@latest  # Go
#
# Generate the GIF:
#   cd demo && vhs demo.tape
#
# Output: ../docs/assets/demo.gif

Output ../docs/assets/demo.gif

Set Shell bash
Set FontSize 14
Set Width 900
Set Height 600
Set FontFamily "JetBrains Mono"
Set Theme "Catppuccin Mocha"
Set Padding 12
Set FrameRate 30

# Brief pause at the start
Sleep 800ms

Type "bash mock-install.sh"
Enter

# OS detection + Docker check
Wait+Line "Docker is installed"
Sleep 400ms

# Configuration banner
Wait+Line "Configuration"
Sleep 300ms

# Domain prompt — simulate typing with realistic speed
Wait+Line "Primary domain"
Sleep 200ms
Type "yourdomain.com"
Enter
Sleep 300ms

# Let's Encrypt email
Wait+Line "Let's Encrypt email"
Sleep 200ms
Type "you@example.com"
Enter
Sleep 300ms

# Cloudflare token (shown as bullets in mock script)
Wait+Line "Cloudflare API Token"
Sleep 400ms

# Tunnel name (press Enter = default proxlio)
Wait+Line "Tunnel name"
Sleep 300ms
Enter
Sleep 300ms

# Install directory (press Enter = default ~/proxlio)
Wait+Line "Installation directory"
Sleep 300ms
Enter
Sleep 400ms

# Config summary
Wait+Line "Proceed"
Sleep 500ms
Type "Y"
Enter
Sleep 400ms

# Install steps
Wait+Line "Port 53"
Sleep 300ms
Wait+Line "docker-compose.yml written"
Sleep 300ms
Wait+Line "Scripts copied"
Sleep 300ms

# Tunnel setup
Wait+Line "Setting up Cloudflare"
Sleep 1500ms
Wait+Line "Tunnel token saved"
Sleep 400ms

# Stack launch
Wait+Line "Container cloudflared"
Sleep 600ms
Wait+Line "NPM is ready"
Sleep 500ms

# Final summary
Wait+Line "Installation complete"

Sleep 3s
