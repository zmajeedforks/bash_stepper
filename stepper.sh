# stepper.sh

################################################################################
# MIT License
#
# Copyright (c) 2024-2026 Zartaj Majeed
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
################################################################################

# bash utility functions to source into script

shopt -s expand_aliases

# for debug trap behavior to control execution of next command
shopt -s extdebug

shopt -s extglob

# enable history without special characters like bang ! and without saving commands in history file
unset HISTFILE histchars
set -o history

function stepper_run_noninteractive {
  stepper_config[interactive]=false
}

function stepper_list_steps {
  stepper_config[mode]=list
  trap list_mode_trap debug
}

# global variables
declare -A stepper_config=(
  [disable_all_commands]=false
  [interactive]=true
  [mode]=normal
)

declare confirm_step_label=""
declare confirm_step_msg=""
declare stepper_list_cmd=false

# a queue of commands extracted from a block like a function or if-then block that has a single history entry
declare -a confirm_step_cmds_queue

# head of block commands queue
declare confirm_step_cmds_queue_head

# replace plain bash variable references with values in expression
# usage: confirm_step_expandvars filled_expression "$expression_with_variables"
# expanded expression is returned in arg 1

function confirm_step_expandvars {
  local -n expanded_ref=$1
  shift
  local s=$*

#  echo "confirm_step_expandvars: s \"$s\""
# handle for-in-loop
  if [[ $s =~ ^[$' \t']*for[$' ']+([_[:alnum:]]+)[$' ']+in ]]; then
    local loop_variable=${BASH_REMATCH[1]}
#    echo "confirm_step_expandvars: loop_variable \"$loop_variable\""
  fi

# handle assignment of command substitution to variable
# assignment is stripped along with command substitution operator annd command is extracted for variable expansion
# command is not run
# cmdout=$(curl $url) becomes "curl $url"
# pattern is ^[$' \t']*[_[:alnum:]]+=\$\((.*)\) ]] && s=${BASH_REMATCH[1]}
#[[ $s =~ ^[$' \t']*[_[:alnum:]]+=\$\((.*)\) ]] && s=${BASH_REMATCH[1]}
if [[ $s =~ ^[$' \t']*[_[:alnum:]]+=\$\((.*)\) ]]; then
  s=${BASH_REMATCH[1]}
fi

# regex match examples
# curl --output-dir $downloaddir -LO https://get.helm.sh/$helm_zipfile
# unzip -j -o -d $toolsdir ${downloaddir}/${helm_zipfile} windows-amd64/helm.exe
# regex has 5 groups /(no variables) ( ($varname) | (${varname}) | (${varname[...]}) )/, only group 1 and 2 captures are used, groups 3, 4, 5 captures are ignored
# group 3 is simple variable without braces ike $helm_zipfile
# group 4 is simple variable with braces like ${downloaddir}
# group 5 is array variable with key like ${kindOpts[clustername]}
  local pat='^([^$]*)((\$[a-zA-Z_0-9]+)|(\$\{[a-zA-Z_0-9]+\})|(\$\{[a-zA-Z_0-9]+\[[^]]+\]\}))'

# progressive regex matching loop over s
  for ((;;)); do
    [[ $s =~ $pat ]] || break
# m1 is initial substring without variables group 1
    local m1=${BASH_REMATCH[1]}
# m2 is matched variable group 2, same as group 3 $varname or group 4 ${varname}
    local m2=${BASH_REMATCH[2]}
# strip $ or ${} from m2 to get variable name then use indirection to get value, another simpler but riskier way is eval local var=$m2
    [[ ${m2:1:1} == "{" ]] && varname=${m2:2:${#m2} - 3} || varname=${m2:1}
#    echo "confirm_step_expandvars: varname \"$varname\""
    if [[ $varname != $loop_variable ]]; then
#    echo "confirm_step_expandvars: varname $varname does not match loop_variable \"$loop_variable\""
# indirect reference to value of variable whose name is $m2, works for simple variable names and array with key names
    local val=${!varname}
# replace variable with its value
    expanded_ref+="$m1$val"
  else
#    echo "confirm_step_expandvars: varname $varname matches loop_variable \"$loop_variable\""
    expanded_ref+="${BASH_REMATCH[0]}"
    fi
# skip past end of matched portion to continue matching remaining string
#  echo "confirm_step_expandvars: expansion so far \"$expanded_ref\""
    s=${s:${#BASH_REMATCH[0]}}
#  echo "confirm_step_expandvars: remaining s \"$s\""
  done
# append trailing part of line left over after matching loop
  expanded_ref+=$s
}

# runs immediately before command that follows call to stepper_confirm_step
# contains interactive prompt for user to confirm next command

function confirm_step_trap {
# unset debug trap for stepper_confirm_step to run all its commands without coming back here
  if [[ $BASH_COMMAND == stepper_confirm_step\ * ]]; then
    trap - debug
    return 0
  fi
  local cmdsblock="$(history 1 | sed -E '1s/^ *[0-9]+ +//')"
  local called_from_line=${BASH_LINENO[0]}
# make default step message from line number of step command like "Run command at line 15"
  [[ -z $confirm_step_msg ]] && confirm_step_msg="Run command at line $called_from_line"

# unset debug trap
  (( confirm_step_multicmds_idx + 1 == confirm_step_multicmds_count )) && trap - debug
  local next_cmd
# return confirmation value from first command in multicommand step
  if (( confirm_step_multicmds_idx++ > 0 )); then
    confirm_step_expandvars next_cmd "$BASH_COMMAND"
    if (( confirm_step_multicmds_rv == 0 )); then
      echo "$next_cmd"
    else
      echo "Skip Step $confirm_step_label command $confirm_step_multicmds_idx: $next_cmd"
    fi
    return $confirm_step_multicmds_rv
  fi

  local next_cmd_with_vars

# get next command from commands queue if not empty or directly from history
  if (( confirm_step_cmds_queue_head < ${#confirm_step_cmds_queue[*]} )); then
    next_cmd_with_vars=${confirm_step_cmds_queue[confirm_step_cmds_queue_head]}
    let ++confirm_step_cmds_queue_head
    if (( confirm_step_cmds_queue_head == ${#confirm_step_cmds_queue[*]} )); then
      confirm_step_cmds_queue=()
    fi
  else
# use history instead of BASH_COMMAND to get complete pipelines and unexpanded aliases
# sed strips initial history number
    next_cmd_with_vars="$(history 1 | sed -E '1s/^ *[0-9]+ +//')"
#    echo "confirm_step_trap: history \"$(history 1)\""
  fi

  confirm_step_expandvars next_cmd "$next_cmd_with_vars"

# print message and next command if noninteractive
  if ! ${stepper_config[interactive]}; then
    echo "Step $confirm_step_label: $confirm_step_msg"
    echo "$next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi

  if [[ -n $skip_till_step_label ]]; then
    if [[ $skip_till_step_label != $confirm_step_label ]]; then
      echo "Step $confirm_step_label: $confirm_step_msg"
      if (( confirm_step_multicmds_count > 1 )); then
        echo "Skip Step $confirm_step_label command 1: $next_cmd"
      else
        echo "Skip Step $confirm_step_label: $next_cmd"
      fi
      confirm_step_multicmds_rv=1
      return 1
    else
      skip_till_step_label=
    fi
  fi

  if [[ -n $run_till_step_label ]]; then
    if [[ $run_till_step_label != $confirm_step_label ]]; then
      echo "Step $confirm_step_label: $confirm_step_msg"
      echo "$next_cmd"
      confirm_step_multicmds_rv=0
      return 0
    else
      run_till_step_label=
    fi
  fi

# ask to run next command
# case-insensitive response is single character
# y: yes, run next command, space and newline act as y
# q: quit, exit script immediately
# s: skip all steps till step entered at followup prompt
# r: run all steps non-interactively till step entered at second prompt, or till termination if no label entered
# n: no, skip next command, any other character acts as n

  read -N1 -p "Step $confirm_step_label: $confirm_step_msg? [y/n/q/j/r] " <> /dev/tty 1>&0

# process response
# no extra newline if response is newline itself
  [[ $REPLY == $'\n' ]] || echo

# q to quit program
  [[ $REPLY == [qQ] ]] && exit

  if false; then
# r to print and run all remaining steps without prompting
  if [[ $REPLY == [rR] ]]; then
    stepper_config[interactive]=false
    echo "$next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi

  else

# r to run all steps till step with label entered at second prompt
  if [[ $REPLY == [rR] ]]; then
    IFS= read -r -p "Run till Step? " run_till_step_label <> /dev/tty 1>&0
# trim whitespace around response
    run_till_step_label=${run_till_step_label##*( )} 
    run_till_step_label=${run_till_step_label%%*( )} 
    if [[ -z $run_till_step_label ]]; then
      stepper_config[interactive]=false
    fi
    echo "Run.1: $next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi
  fi

# y to run next command, space and newline act as y
  if [[ $REPLY = [yY$' \n'] ]]; then
    echo "$next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi

# s to skip steps till step with label entered at second prompt, skipping all steps in between
  if [[ $REPLY == [jJ] ]]; then
    IFS= read -r -p "Jump to Step? " skip_till_step_label <> /dev/tty 1>&0
# trim whitespace around response
    skip_till_step_label=${skip_till_step_label##*( )} 
    skip_till_step_label=${skip_till_step_label%%*( )} 
  fi

# n to skip next command, all other characters act as n
  if (( confirm_step_multicmds_count > 1 )); then
    echo "Skip Step $confirm_step_label command 1: $next_cmd"
  else
    echo "Skip Step $confirm_step_label: $next_cmd"
  fi
  confirm_step_multicmds_rv=1
  return 1
}

# a step is the next command to confirm with message
# step has optional label that can be any string
# optional arg 1 is step message, default is "Run command at line 15"
# optional arg 2 is step label, default is line_14
# optional arg 3 is number of commands in multicommand step, default is 1
# example:
# script contains the two line:
# stepper_confirm_step "Create Podman machine" podman_1
# podman machine init
# here step command is "podman machine init", step message is "Create Podman machine", step label is podman_1
# user sees:
# Step podman_1: Create Podman machine? [y/n/q/s/r]
# Step podman_1: Create Podman machine? [y/n/q/j/r]
# If user types y, "Step podman_1: podman machine init" is printed and command runs
# If user types n, "Skip Step podman_1: podman machine init" is printed and command does not run
# If user types q, program exits, nothing is printed and command does not run
# If user types s, a secondary prompt appears "Skip till Step?". Say user types podman_9. Then "Skip Step podman_1: podman machine init" is printed and command does not run. All following steps until step podman_9 are skipped with a skip message. Normal prompting resumes at step podman_9.
# If user types j, a secondary prompt appears "Jump to Step?". Say user types podman_9. Then "Skip Step podman_1: podman machine init" is printed and command does not run. All following steps until step podman_9 are skipped with a skip message. Normal prompting resumes at step podman_9.
# If user types r, a secondary prompt appears "Run till Step?". Say user types podman_9. The next command runs and all following steps are printed and run till step podman_9. Normal prompting resumes at step podman_9. All steps run till termination if no step label is entered at secondary prompt.
# possible r mode enhancement could be to track exit status of step command and switch to interactive mode on first error
#
# limitations:
# command substitution assignment to variable is handled but any other inline command substitution is not handled
# this works: cmdout=$(curl $url)
# this does not work: for node in $($kind get nodes -n $cluster); do ... done
# instead evaluate the inline command substitution before the step and replace it with a variable
# stepper_confirm_step inside nested block constructs probably won't work, like if-then inside for-in-loop or a block inside a function
# stepper_confirm_step inside a block like if-then where the step itself is a block like for-in-loop probably won't work either

function stepper_confirm_step {
  local called_from_line=${BASH_LINENO[0]}
# default step message set inside debug trap
  confirm_step_msg=$1
# make default step label from step line number like line_14
  confirm_step_label=${2:-line_$called_from_line}

  if [[ ${stepper_config[mode]} == list ]]; then
    stepper_list_cmd=true
    trap list_mode_trap debug
    return
  fi

# trap runs for idx >= 0 && idx < count
# trap cleared for idx == count
# trap return value saved for idx 0
# trap returns saved return value for idx > 0 && idx < count
  confirm_step_multicmds_count=${3:-1}
  confirm_step_multicmds_idx=0
  confirm_step_multicmds_rv=

# check if commands queue should be filled from function or non-function block of commands like if-then-fi
  if (( ${#confirm_step_cmds_queue[*]} == 0 )); then
    if ((${#FUNCNAME[*]} > 2)); then
# detect stepper_confirm_step called from inside function because function array size is at least 3 like [stepper_confirm_step, undo, main]
      local funcname=${FUNCNAME[1]}
      local funcblock=$(declare -f $funcname)
      if [[ $funcblock =~ [^\;]$'\n'\} ]]; then
# make sure last command in function has semicolon terminator like all other commands
        funcblock=${funcblock/%$'\n'\}/\;$'\n'\}}
      fi
# strip function name, empty parentheses and opening brace, func () {, also strip closing brace
        funcblock=${funcblock#$funcname () $'\n'{ $'\n'}
        funcblock=${funcblock%\}}
      confirm_step_extract_cmds "$funcblock"
    else
#    echo "confirm_step_trap: nonfuncblock history \"$(history 1)\""
      local nonfuncblock="$(history 1 | sed -E '1s/^ *[0-9]+ +//')"
#    echo "confirm_step_trap: nonfuncblock \"$nonfuncblock\""
      if [[ $nonfuncblock =~ [^[:space:]]+.*[[:\<:]]stepper_confirm_step[[:\>:]] ]]; then
# detect stepper_confirm_step called from inside non-function block of commands because history entry has non-whitespace before stepper_confirm_step call
        confirm_step_extract_cmds "$nonfuncblock"
#    echo "confirm_step_trap: nonfuncblock got cmds \"$cmds\""
      fi
    fi
  fi

# set debug trap to confirm next command
  trap confirm_step_trap debug
}

# fill confirm_step_cmds_queue with step commands parsed out of block of commands passed as argument
# block of commands could be function, if-then-fi or anything because this just matches anything terminated by semicolon and extracts the command that immediately follows stepper_confirm_step command

# each command inside a function ends with a semicolon followed by newline - this is from the output of bash declare -f
# since semicolon-newline is assumed to terminate a complete command, any command with an embedded semicolon at the end of line will break this script

function confirm_step_extract_cmds {

  local cmdsblock=$1

  confirm_step_cmds_queue=()
  confirm_step_cmds_queue_head=0

  local save_cmd=false
  local s=$cmdsblock

# keep matching commands with semicolon terminator
  for ((;;)); do
    [[ $s =~ \;$'\n' ]] || break
# strip matched portion to continue matching remaining string
    local allbefore=${s%%;$'\n'*}
    local allafter=${s#*;$'\n'}
    s=${allafter##*( )}

    local cmd=${allbefore##*( )}
    if $save_cmd; then
# clear flag and add command to commands queue
      confirm_step_cmds_queue+=("$cmd")
      save_cmd=false
    elif [[ $cmd =~ [[:\<:]]stepper_confirm_step[[:\>:]] ]]; then
# set flag to add command that follows stepper_confirm_step to commands queue
      save_cmd=true
    fi
  done
}

function list_mode_trap {
# unset debug trap for stepper_confirm_step to run all its commands without coming back here
  if [[ $BASH_COMMAND == stepper_confirm_step\ * ]]; then
    trap - debug
    return 0
  fi

  if $stepper_list_cmd; then
    local called_from_line=${BASH_LINENO[0]}
    [[ -z $confirm_step_msg ]] && confirm_step_msg="Run command at line $called_from_line"
    echo "$confirm_step_label: $confirm_step_msg"
    stepper_list_cmd=false
    return 1
  fi

  return 1
}

function disable_commands_trap {
  if [[ $BASH_COMMAND == stepper_enable_commands ]]; then
    trap - debug
    stepper_config[disable_all_commands]=false
    return 0
  fi
  return 1
}

function stepper_disable_commands {

  stepper_config[disable_all_commands]=true
  trap disable_commands_trap debug

}

function stepper_enable_commands {
  :
}

function confirm_step_usage {
  echo "This script runs interactive steps. Each step is a significant command that must be confirmed or skipped."
  echo "A label and message is printed for each step"
  echo "The response is a single case-insensitive character - y/n/q/j/r"
  echo "y: yes, run next command (space and newline act as y)"
  echo "q: quit, exit script immediately"
  echo "j: jump to step with label entered at second prompt, skipping all steps in between"
  echo "r: run all steps non-interactively till label entered at second prompt or till termination if no label entered"
  echo "n: no, don't run next command (all other characters act as n)"
}


