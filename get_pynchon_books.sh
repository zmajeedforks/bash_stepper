#!/bin/bash

# get_pynchon_books.sh

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

# source stepper.sh from same directory as this script
. ${BASH_SOURCE[0]%/*}/stepper.sh || exit 2

function usage {
  echo "Usage: get_pynchon_books.sh [-h] [-l] [-r]"
  echo "Example of using stepper.sh to interactively control commands execution"
  echo "-l: list all steps"
  echo "-r: run entire script noninteractively"
  echo "-h: help"
  stepper_usage
}

function make_books_tsv_from_wiki_table {

  stepper_confirm_step "Extract books from wiki table" books_tsv_from_wiki_table
  jq -r '.parse.wikitext."*"' < bib_wikitext.json |
  sed -nE '
# Books section
  /^=== Books ===$/,/^$/ {
# wiki table between {| ... |}
    /^\{\|/,/^\|\}$/ {

# strip leading and trailing space
      s/^ +//
      s/ +$//
      /^$/d

# new field
# add tab delimiter and accumulate
# causes every row to start with extra newline and tab before first field that we remove before printing

    /^((\|[^-}])|!) */ {
        s//\t/
        H
        d
      }

# new row is |-, table end is |}
# emit previous row
# remove extra first tab

      /^\|-|\|\}$/ {
# get previous completed row from holdspace
        g
# strip extra newline and tab at start of row
        s/^\n\t//
        s/\n//g
        p
# clear holdspace
        s/.*//
        x
        d
      }

# known continuation of field on new line      
      /^\* / {
        H
        d
      }
    }
  }
  ' |
  cut -f1-6 |
  awk -F'\t' '
    BEGIN {OFS = "\t"}

# sample
# {{plainlist|* {{LCCN|638634}}* {{OCLC|288349}}}}
    {
      for(i = 1; i <= NF; ++i) {
        if($i !~ /^\{\{plainlist\| *\* */) {
          continue
        }
        $i = gensub(/^\{\{plainlist\| *\* *(.+)\}\}/, "\\1", 1, $i)
        $i = gensub(/\* /, ", ", "g", $i)
        $i = gensub(/\{\{(.+?)\}\}/, "\\1", "g", $i)
        $i = gensub(/(LCCN|OCLC|ISBN)\|/, "\\1 ", "g", $i)
      }
    }

# sample
# ''[[V.]]''
# {{sort|Crying of Lot 49, The|''[[The Crying of Lot 49]]''}}
# [[J. B. Lippincott & Co.|Lippincourt]] (Philadelphia)
# Novella{{NoteTag|name=Story|In the introduction to ''Slow Learner'', Pynchon set the title as "The Crying of Lot 49"—within double [[quotation mark]]s, rather than italics—and described it as a "story" that had been "marketed as a 'novel{{'"}}.{{sfn|Pynchon|1984|p=22}}}}
    {
      for(i = 1; i <= NF; ++i) {
        $i = gensub(/\{\{sort\|[^}]+\|([^}]+)\}\}/, "\\1", 1, $i)
        $i = gensub(/\{\{NoteTag\|.+\}\}$/, "", 1, $i)
        $i = gensub(/(\x27{2})?\[\[([^]]+)\]\](\x27{2})?/, "\\2", "g", $i)
      }
    }

# sample
# Mar 18,<br>1963
    {
      for(i = 1; i <= NF; ++i) {
# strip remnants of wikitext templates
        $i = gensub(/^.*\| */, "", 1, $i)
# replace html linebreaks with space
        $i = gensub(/<br>/, " ", "g", $i)
      }
    }

    1
  '
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
  stepper_list_steps
fi

if [[ $mode == noninteractive ]]; then
  stepper_run_noninteractive
fi

stepper_confirm_step
date

stepper_confirm_step "Download Pynchon Wikipedia page" download_pynchon_page
wget --convert-links -O pynchon_wiki.html https://en.wikipedia.org/wiki/Thomas_Pynchon

stepper_confirm_step "Extract Pynchon bibliography link" extract_bib_link
cmdout=$(grep -o 'Main article:.*Thomas Pynchon bibliography' pynchon_wiki.html |
  sed -E '
    s/^(.*)href="([^"]+)"(.*)/[href]=\2\t\1\3/
    s/(\t.*)title=("[^"]+")(.*)/ [title]=\2\1\3/
    s/\t.*//
  '
)
declare -A props="($cmdout)"
bib_url=${props[href]}
bib_title=${props[title]}

stepper_confirm_step "Download Pynchon bibliography from $bib_url" download_bib_page
wget -O bib_wiki.html $bib_url

stepper_confirm_step "Download page info for Pynchon bibliography page $bib_title"
wget -O bib_info.json "https://en.wikipedia.org/w/api.php?action=query&format=json&utf8&titles=$bib_title&prop=pageprops"

stepper_confirm_step "Get page id for Pynchon bibliography page"
bib_pageid=$(jq -r '.query.pages | keys[0]' < bib_info.json)

stepper_confirm_step "Download wikitext for Pynchon bibliography page id $bib_pageid" download_bib_wikitext
wget -O bib_wikitext.json "https://en.wikipedia.org/w/api.php?action=parse&format=json&utf8&disabletoc&prop=wikitext&section=1&pageid=$bib_pageid"

make_books_tsv_from_wiki_table

