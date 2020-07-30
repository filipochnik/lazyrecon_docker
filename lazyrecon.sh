#!/bin/bash

massdnsWordlist=$HOME/tools/SecLists/Discovery/DNS/clean-jhaddix-dns.txt
massdnsResolvers1="$HOME/tools/massdns/lists/resolvers.txt"
outputDirectory="./lazyrecon_results"
outputFolder=
resultsFolder=
domain=

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

SECONDS=0

usage() {
    echo -e "Usage: $0 -d domain [-o \"outputDirectory\"]\n" 1>&2
    exit 1
}

while getopts ":d:o:" options; do
    case "${options}" in
    d)
        domain=${OPTARG}
        ;;
    o)
        outputDirectory=${OPTARG}
        ;;
    *)
        usage
        ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "${domain}" ]; then
    usage
    exit 1
fi

log() {
    echo "${green}[$(date -u '+%Y-%m-%d %H:%M:%S')] $1${reset}"
}

sort_unique() {
    file=$1
    cat "$file" | sort -u | sponge "$file"
}

add_candidates() {
    file=$1
    cat "$outputFolder/$file" >> "$outputFolder/candidates.txt"
    sort_unique "$outputFolder/candidates.txt"
}

move_results() {
    mv "$outputFolder/domains.txt" "$resultsFolder"
    mv "$outputFolder/cnames.txt" "$resultsFolder"
}

recon() {
    log "Starting recon on $domain"

    generate_candidates
    verify
    move_results

    log "Scan for $domain finished successfully"
    duration=$SECONDS
    log "Scan completed in $(($duration / 60)) minutes and $(($duration % 60)) seconds."
}

generate_candidates() {
    touch "$outputFolder/candidates.txt"

    log "Finding domains using Project Sonar data"
    curl -s "https://dns.bufferover.run/dns?q=$domain" 2>/dev/null | jq -r '.FDNS_A,.RDNS | .[]?' | sed 's/\*\.//g' | cut -d ',' -f2 | grep -F ".$domain" >"$outputFolder/sonar.txt"
    add_candidates "sonar.txt"

    log "Finding subdomains using Amass"
    amass enum -passive -nolocaldb -d "$domain" >"$outputFolder/amass.txt"
    add_candidates "amass.txt"

    log "Running DNSgen for new possible domain name combinations"
    dnsgen "$outputFolder/candidates.txt" >"$outputFolder/dnsgen.txt"
    add_candidates "dnsgen.txt"

    log "Running subbrute"
    $HOME/tools/massdns/scripts/subbrute.py "$massdnsWordlist" "$domain" >"$outputFolder/subbrute.txt"
    add_candidates "subbrute.txt"
}

extract_domains_from_massdns() {
    massdnsOutput=$1
    dst=$2
    cat "$massdnsOutput" | cut -d' ' -f1 | grep -v "[*]" | sed -e 's/\.$//' | sponge "$dst"
    sort_unique "$dst"
}

verify() {
    log "Starting verification"

    log "Starting MassDNS subdomain discovery"
    cat "$outputFolder/candidates.txt" | $HOME/tools/massdns/bin/massdns -r "$massdnsResolvers1" -t A -q -o S >"$outputFolder/mass1.txt"

    log "Verifying found domains with reliable resolvers"
    extract_domains_from_massdns "$outputFolder/mass1.txt" "$outputFolder/mass1.txt"
    printf "1.1.1.1\n8.8.8.8\n9.9.9.9\n" > resolvers2.txt
    cat "$outputFolder/mass1.txt" | $HOME/tools/massdns/bin/massdns -r "resolvers2.txt" -t A -q -o S >"$outputFolder/mass.txt"

    log "Extracting CNAMEs"
    cat "$outputFolder/mass.txt" | grep CNAME >>"$outputFolder/cnames.txt"

    extract_domains_from_massdns "$outputFolder/mass.txt" "$outputFolder/domains.txt"
}

logo() {
    #can't have a bash script without a cool logo :D
    echo "${red}
 _     ____  ____ ___  _ ____  _____ ____  ____  _
/ \   /  _ \/_   \\\  \///  __\/  __//   _\/  _ \/ \  /|
| |   | / \| /   / \  / |  \/||  \  |  /  | / \|| |\ ||
| |_/\| |-||/   /_ / /  |    /|  /_ |  \__| \_/|| | \||
\____/\_/ \|\____//_/   \_/\_\\\____\\\____/\____/\_/  \\|
${reset}                                                      "
}

main() {
    clear
    logo

    outputFolder="$outputDirectory/$domain/$foldername/output"
    resultsFolder="$outputDirectory/$domain/$foldername/results"
    mkdir -p "$outputFolder"
    mkdir -p "$resultsFolder"

    recon

    stty sane
    tput sgr0
}

todate=$(date +"%Y-%m-%d")
foldername=recon-$todate
main "$domain"
