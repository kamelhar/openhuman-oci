# VHS tape: records deploy/scripts/demo.sh into media/demo.mp4 and media/demo.gif
Output media/demo.mp4
Set Shell bash
Env PATH "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
Env OCI_PROFILE "API_FREE_TIER"
Env OCI_HOME_REGION "ca-toronto-1"
Env DEMO_SSH_PORT "2222"
Env PYTHONWARNINGS "ignore"
Set FontSize 14
Set Width 1600
Set Height 1000
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms
Set Padding 18
Type "clear && ./deploy/scripts/demo.sh"
Enter
Wait+Screen@600s /DEMO_DONE/
Sleep 4s
