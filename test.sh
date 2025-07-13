#!/usr/bin/env sh

rg --files --hidden --follow --glob '!.git/*' | while IFS= read -r path; do
    # We remove everything from the beginning (`##`) up to and including the last slash (`*/`) to
    # get the basename of the path.
    basename="${path##*/}"

    # We remove the last slash and everything after it (`%/*`) from the end to get the dirname of the
    # path.
    dirname="${path%/*}"

    # There are two cases to handle here, namely:
    #
    # - the path has no dirname, _i.e.,_ dirname == path, and
    # - the path has a dirname.
    if [[ "$dirname" == $path ]]; then
        printf "$(tput bold)$basename$(tput sgr0)\n"
    else
        # NOTE: If the terminal does not support 256-colour, replace `setaf 244` with `dim`.
        printf "$(tput setaf 244)$dirname/$(tput sgr0)$(tput bold)$basename$(tput sgr0)\n"
    fi
done
