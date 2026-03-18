# Bash stepper script

`stepper.sh` is a library of functions to control the execution of commands in a bash script

Call `stepper_confirm_step` right before any command to trace and control

Let's look at a simple webscraping example. Let's get a list of books written by Thomas Pynchon in tab-delimited format.

We start with the Wikipedia page for Thomas Pynchon. It has a link to a bibliography of Pynchon that includes all his books.

Our plan is to write a script `get_pynchon_books.sh` that does this in four steps.

1. Download Pynchon Wikipedia page
2. Scrape the link to his bibliography from the downloaded page
3. Download Pynchon bibliography page
4. Generate a tab-delimited list of his books from the downloaded bibliography page

Let's give each step a name and a brief description. Let's also summarize how to perform the step.

1. Download Pynchon Wikipedia page
Name: `download_pynchon_page`
Description: Download Pynchon Wikipedia page
Commands: Use `wget` to download Wikipedia page

2. Scrape the link to his bibliography from the downloaded page
Name: extract_biblio_link
Description: Extract Pynchon bibliography link
Commands: Use `grep` and `sed` to scrape link of bibliography page from bibliography section in downloaded page. We'll actually get the title of the bibliography page too in order to retrieve it as JSON data by title.

3. Download Pynchon bibliography page info
Description: Download Pynchon bibliography page info
Commands: `wget` Wikipedia API for page info by title

4. Get page ID of bibliography page
Description: Get page ID of bibliography page
Commands: `jq` to extract JSON data from downloaded page info. Need page id to get bibliography as JSON data.

5. Download bibliography as JSON data
Name: download_biblio_wikitext
Description: Download wikitext for bibliography by page id
Commands: `wget` Wikipedia API for article wikitext by page id

6. Generate tab-delimited table of books from downloaded wikitext
Name: books_tsv_from_wiki_table
Description: Extract books from wiki table
Commands: Use `jq` to extract wiki table. Convert wiki table to tab-delimited records with `sed` and `awk`.

```bash
#!/bin/bash

# source stepper.sh from same directory as this script
. ${BASH_SOURCE[0]%/*}/stepper.sh || exit 2

stepper_confirm_step "Download Pynchon Wikipedia page" download_pynchon_page
wget --convert-links -O pynchon_wiki.html https://en.wikipedia.org/wiki/Thomas_Pynchon

stepper_confirm_step "Extract Pynchon bibliography link" extract_biblio_link
cmdout=$(grep -o 'Main article:.*Thomas Pynchon bibliography' pynchon_wiki.html |
  sed -E '
    s/^(.*)href="([^"]+)"(.*)/[href]=\2\t\1\3/
    s/(\t.*)title=("[^"]+")(.*)/ [title]=\2\1\3/
    s/\t.*//
  '
)
declare -A props="($cmdout)"
biblio_url=${props[href]}
biblio_title=${props[title]}

stepper_confirm_step "Download Pynchon bibliography from $biblio_url" download_biblio_page
wget -O biblio_wiki.html $biblio_url

stepper_confirm_step "Download page info for Pynchon bibliography page $biblio_title"
wget -O biblio_info.json "https://en.wikipedia.org/w/api.php?action=query&format=json&utf8&titles=$biblio_title&prop=pageprops"

stepper_confirm_step "Get page id for Pynchon bibliography page"
biblio_pageid=$(jq -r '.query.pages | keys[0]' < biblio_info.json)

stepper_confirm_step "Download wikitext for Pynchon bibliography page id $biblio_pageid" download_biblio_wikitext
wget -O biblio_wikitext.json "https://en.wikipedia.org/w/api.php?action=parse&format=json&utf8&disabletoc&prop=wikitext&section=1&pageid=$biblio_pageid"

make_books_tsv_from_wiki_table
```

