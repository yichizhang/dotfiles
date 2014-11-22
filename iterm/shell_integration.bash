#!/bin/bash
# This is based on "preexec.bash" but is customized for iTerm2.

# Note: this module requires 2 bash features which you must not otherwise be
# using: the "DEBUG" trap, and the "PROMPT_COMMAND" variable.  preexec_install
# will override these and if you override one or the other this _will_ break.

# This is known to support bash3, as well as *mostly* support bash2.05b.  It
# has been tested with the default shells on MacOS X 10.4 "Tiger", Ubuntu 5.10
# "Breezy Badger", Ubuntu 6.06 "Dapper Drake", and Ubuntu 6.10 "Edgy Eft".


# Copy screen-run variables from the remote host, if they're available.

# Saved copy of your PS1. Changes to PS1 from here on are ignored as it is
# re-set from PROMPT_COMMAND.
orig_ps1="${PS1}"

# This variable describes whether we are currently in "interactive mode";
# i.e. whether this shell has just executed a prompt and is waiting for user
# input.  It documents whether the current command invoked by the trace hook is
# run interactively by the user; it's set immediately after the prompt hook,
# and unset as soon as the trace hook is run.
preexec_interactive_mode=""

# tmux and screen are not supported; even using the tmux hack to get escape
# codes passed through, ncurses interferes and the cursor isn't in the right
# place at the time it's passed through.
if ( [ x"$TERM" != xscreen ] ); then
  # Default do-nothing implementation of preexec.
  function preexec () {
      true
  }

  # Default do-nothing implementation of precmd.
  function precmd () {
      true
  }

  # This function is installed as the PROMPT_COMMAND; it is invoked before each
  # interactive prompt display.  It sets a variable to indicate that the prompt
  # was just displayed, to allow the DEBUG trap, below, to know that the next
  # command is likely interactive.
  function preexec_invoke_cmd () {
      last_hist_ent="$(history 1)";
      precmd;
      # This is an iTerm2 addition to try to work around a problem in the
      # original preexec.bash.
      # When the PS1 has command substitutions, this gets invoked for each
      # substitution and each command that's run within the substitution, which
      # really adds up. It would be great if we could do something like this at
      # the end of this script:
      #   PS1="$(prompt_prefix)$PS1($prompt_suffix)"
      # and have prompt_prefix set a global variable that tells precmd not to
      # output anything and have prompt_suffix reset that variable.
      # Unfortunately, command substitutions run in subshells and can't
      # communicate to the outside world. 
      # Instead, we have this workaround. We save the original value of PS1 in
      # $orig_ps1. Then each time this function is run (it's called from
      # PROMPT_COMMAND just before the prompt is shown) it will change PS1 to a
      # string without any command substitutions by doing eval on orig_ps1. At
      # this point preexec_interactive_mode is still the empty string, so preexec
      # won't produce output for command substitutions.
      export PS1="\[$(prompt_prefix)\]$(eval "echo \"$orig_ps1\"")\[$(prompt_suffix)\]"
      preexec_interactive_mode="yes";
  }

  # This function is installed as the DEBUG trap.  It is invoked before each
  # interactive prompt display.  Its purpose is to inspect the current
  # environment to attempt to detect if the current command is being invoked
  # interactively, and invoke 'preexec' if so.
  function preexec_invoke_exec () {
      if [[ -n "$COMP_LINE" ]]
      then
          # We're in the middle of a completer.  This obviously can't be
          # an interactively issued command.
          return
      fi
      if [[ -z "$preexec_interactive_mode" ]]
      then
          # We're doing something related to displaying the prompt.  Let the
          # prompt set the title instead of me.
          return
      else
          # If we're in a subshell, then the prompt won't be re-displayed to put
          # us back into interactive mode, so let's not set the variable back.
          # In other words, if you have a subshell like
          #   (sleep 1; sleep 2)
          # You want to see the 'sleep 2' as a set_command_title as well.
          if [[ 0 -eq "$BASH_SUBSHELL" ]]
          then
              preexec_interactive_mode=""
          fi
      fi
      if [[ "preexec_invoke_cmd" == "$BASH_COMMAND" ]]
      then
          # Sadly, there's no cleaner way to detect two prompts being displayed
          # one after another.  This makes it important that PROMPT_COMMAND
          # remain set _exactly_ as below in preexec_install.  Let's switch back
          # out of interactive mode and not trace any of the commands run in
          # precmd.

          # Given their buggy interaction between BASH_COMMAND and debug traps,
          # versions of bash prior to 3.1 can't detect this at all.
          preexec_interactive_mode=""
          return
      fi

      # In more recent versions of bash, this could be set via the "BASH_COMMAND"
      # variable, but using history here is better in some ways: for example, "ps
      # auxf | less" will show up with both sides of the pipe if we use history,
      # but only as "ps auxf" if not.
      hist_ent="$(history 1)";
      local prev_hist_ent="${last_hist_ent}";
      last_hist_ent="${hist_ent}";
      if [[ "${prev_hist_ent}" != "${hist_ent}" ]]; then
          local this_command="$(echo "${hist_ent}" | sed -e "s/^[ ]*[0-9]*[ ]*//g")";
      else
          local this_command="";
      fi;

      # If none of the previous checks have earlied out of this function, then
      # the command is in fact interactive and we should invoke the user's
      # preexec hook with the running command as an argument.
      preexec "$this_command";
  }

  # Execute this to set up preexec and precmd execution.
  function preexec_install () {

      # *BOTH* of these options need to be set for the DEBUG trap to be invoked
      # in ( ) subshells.  This smells like a bug in bash to me.  The null stackederr
      # redirections are to quiet errors on bash2.05 (i.e. OSX's default shell)
      # where the options can't be set, and it's impossible to inherit the trap
      # into subshells.

      set -o functrace > /dev/null 2>&1
      shopt -s extdebug > /dev/null 2>&1

      # Finally, install the actual traps.
      if ( [ x"$PROMPT_COMMAND" = x ]); then
        PROMPT_COMMAND="preexec_invoke_cmd";
      else
        PROMPT_COMMAND="$PROMPT_COMMAND; preexec_invoke_cmd";
      fi
      trap 'preexec_invoke_exec' DEBUG;
  }

  # -- begin iTerm2 customization

  function iterm2_begin_osc {
    printf "\033]"
  }

  function iterm2_end_osc {
    printf "\007"
  }

  # Runs after interactively edited command but before execution
  function preexec() {
    iterm2_begin_osc
    printf "133;C"
    iterm2_end_osc
  }

  function remotehost_and_currentdir() {
    iterm2_begin_osc
    printf "1337;RemoteHost=%s@%s" "$USER" $(hostname -f)
    iterm2_end_osc

    iterm2_begin_osc
    printf "1337;CurrentDir=%s" "$PWD"
    iterm2_end_osc
  }

  function prompt_prefix() {
    iterm2_begin_osc
    printf "133;D;\$?"
    iterm2_end_osc

    remotehost_and_currentdir

    iterm2_begin_osc
    printf "133;A"
    iterm2_end_osc
  }

  function prompt_suffix() {
    iterm2_begin_osc
    printf "133;B"
    iterm2_end_osc
  }

  function print_version_number() {
    iterm2_begin_osc
    printf "1337;ShellIntegrationVersion=1"
    iterm2_end_osc
  }

  preexec_install

  # This is necessary so the first command line will have a hostname and current directory.
  remotehost_and_currentdir
  print_version_number
fi
