#!/bin/bash

# test_stepper.sh

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

. ${BASH_SOURCE[0]%/*}/stepper.sh || exit 2

function usage {
  echo "Usage: test_stepper.sh"
  echo "Interactive commands test script"
  stepper_usage
}

function test_confirm_inside_function {
 
  stepper_confirm_step "Function Step 1" func_step_1
  echo func_step_1_output
  echo

  stepper_confirm_step "Function Step 2" func_step_2
  echo func_step_2_output
  echo

  local step=3
  local numcmds=2
  stepper_confirm_step "Function multicommand Step $step with ${numcmds} commands" func_step_3 $numcmds
  echo func_step_${step}_output_1
  echo func_step_${step}_output_2
  echo

  local cmdout=
  stepper_confirm_step "Function Step 4 with command substitution" func_step_4
  cmdout=$(echo func_step_4_output)
  echo "cmdout \"$cmdout\""
  echo

  stepper_confirm_step "Function last command" func_last_command
  echo func_last_command_output
}

function test_list_steps {
  stepper_list_steps
}

while getopts "hlr" opt; do
  case $opt in
    l)
      list_steps=true
      ;;
    r)
      mode=noninteractive
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
  esac
done
shift $((OPTIND - 1))

if (($# > 0)); then
  usage
  exit 1
fi

: ${mode:=interactive}
: ${list_steps:=false}

if $list_steps; then
  echo "Test stepper_list_steps"
  stepper_list_steps
fi

if [[ $mode == noninteractive ]]; then
  stepper_run_noninteractive
fi

echo "Test stepper_confirm_step in main script"

stepper_confirm_step "Main Step 1" main_step_1
echo main_step_1_output
echo

stepper_confirm_step "Main Step 2" main_step_2
echo main_step_2_output
echo

stepper_confirm_step "Main Step 3 pipeline" main_step_3
echo main_step_3_output | sed 's/$/ through pipeline/'
echo

step=4
numcmds=3
stepper_confirm_step "Main multicommand Step $step with ${numcmds} commands" main_step_${step} $numcmds
echo main_step_${step}_output_1
echo main_step_${step}_output_2
echo main_step_${step}_output_3
echo

cmdout=
stepper_confirm_step "Main Step 5 with command substitution and variable assignment" main_step_5
cmdout=$(echo main_step_5_output)
echo "cmdout \"$cmdout\""
echo

echo "Test stepper_confirm_step inside if-then block"
if true; then
 
  stepper_confirm_step "If-then block Step 1" if_then_block_step_1
  echo if_then_block_step_1_output
  echo

  stepper_confirm_step "If-then block Step 2 with pipeline" if_then_block_step_2
  echo if_then_block_step_2_output |
  cat
  echo

  step=3
  numcmds=2
  stepper_confirm_step "If-then block multicommand Step $step with ${numcmds} commands" if_then_block_step_3 $numcmds
  echo if_then_block_step_${step}_output_1
  echo if_then_block_step_${step}_output_2
  echo

  cmdout=
  stepper_confirm_step "If-then block Step 4 with command substitution" if_then_block_step_4
  cmdout=$(echo if_then_block_step_4_output)
  echo "cmdout \"$cmdout\""
  echo

fi

stepper_confirm_step "Main Step 6" main_step_6
echo main_step_6_output
echo

echo "Test stepper_confirm_step inside function"
test_confirm_inside_function

echo "Test stepper_confirm_step for-loop"
loop_steps="loop_step_1 loop_step_2 loop_step_3"
stepper_confirm_step "For-loop Steps 1 to 3" main_for_loop
for step in $loop_steps; do
  echo "$step"
done

