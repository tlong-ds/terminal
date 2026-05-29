# bunnyshell-shell-integration (zprofile)
#
# See zshenv.zsh for the rationale on the trailing `:`.
{
  _bunnyshell_user_zdotdir="${BUNNYSHELL_USER_ZDOTDIR:-$HOME}"
  [ -f "$_bunnyshell_user_zdotdir/.zprofile" ] && source "$_bunnyshell_user_zdotdir/.zprofile"
  unset _bunnyshell_user_zdotdir
}
:
