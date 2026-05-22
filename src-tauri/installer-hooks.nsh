; "Open in Bunnyshell" shell verbs for folders, folder backgrounds, and drives.
; HKCU matches installer currentUser scope. %V = clicked path.
; NoWorkingDirectory keeps Explorer from overriding %V (System32 on Drive).

!macro NSIS_HOOK_POSTINSTALL
  WriteRegStr HKCU "Software\Classes\Directory\shell\OpenInBunnyshell" "" "Open in Bunnyshell"
  WriteRegStr HKCU "Software\Classes\Directory\shell\OpenInBunnyshell" "Icon" '"$INSTDIR\bunnyshell.exe",0'
  WriteRegStr HKCU "Software\Classes\Directory\shell\OpenInBunnyshell" "NoWorkingDirectory" ""
  WriteRegStr HKCU "Software\Classes\Directory\shell\OpenInBunnyshell\command" "" '"$INSTDIR\bunnyshell.exe" "%V"'

  WriteRegStr HKCU "Software\Classes\Directory\Background\shell\OpenInBunnyshell" "" "Open in Bunnyshell"
  WriteRegStr HKCU "Software\Classes\Directory\Background\shell\OpenInBunnyshell" "Icon" '"$INSTDIR\bunnyshell.exe",0'
  WriteRegStr HKCU "Software\Classes\Directory\Background\shell\OpenInBunnyshell" "NoWorkingDirectory" ""
  WriteRegStr HKCU "Software\Classes\Directory\Background\shell\OpenInBunnyshell\command" "" '"$INSTDIR\bunnyshell.exe" "%V"'

  WriteRegStr HKCU "Software\Classes\Drive\shell\OpenInBunnyshell" "" "Open in Bunnyshell"
  WriteRegStr HKCU "Software\Classes\Drive\shell\OpenInBunnyshell" "Icon" '"$INSTDIR\bunnyshell.exe",0'
  WriteRegStr HKCU "Software\Classes\Drive\shell\OpenInBunnyshell" "NoWorkingDirectory" ""
  WriteRegStr HKCU "Software\Classes\Drive\shell\OpenInBunnyshell\command" "" '"$INSTDIR\bunnyshell.exe" "%V"'
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
  DeleteRegKey HKCU "Software\Classes\Directory\shell\OpenInBunnyshell"
  DeleteRegKey HKCU "Software\Classes\Directory\Background\shell\OpenInBunnyshell"
  DeleteRegKey HKCU "Software\Classes\Drive\shell\OpenInBunnyshell"
!macroend
