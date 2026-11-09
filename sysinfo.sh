#!/bin/bash

SCRIPT_NAME=$(basename "$0")
REPORT_DIR="$HOME/sysinfo_reports"
RUN_ONCE=0
LINE="=================================================="

show_help() {
    echo "Usage: $SCRIPT_NAME [-d directory] [-r] [-h]"
    echo "  -d DIR   folder where reports are saved (default: $REPORT_DIR)"
    echo "  -r       generate a single report and exit"
    echo "  -h       show this help"
}

pause() {
    echo
    read -r -p "Press Enter to return to the menu..."
}

header() {
    echo
    echo "$LINE"
    echo "  $1"
    echo "$LINE"
}

need_cmd() {
    if ! command -v "$1" > /dev/null 2>&1; then
        echo "Error: command '$1' is not available on this system."
        return 1
    fi
    return 0
}

prepare_report_dir() {
    if [ ! -d "$REPORT_DIR" ]; then
        mkdir -p "$REPORT_DIR" 2> /dev/null || {
            echo "Error: cannot create directory '$REPORT_DIR'."
            return 1
        }
        echo "Created report directory: $REPORT_DIR"
    fi
    if [ ! -w "$REPORT_DIR" ]; then
        echo "Error: no write permission for '$REPORT_DIR'."
        return 1
    fi
    return 0
}

system_overview() {
    header "SYSTEM OVERVIEW"
    echo "Hostname      : $(hostname)"
    echo "Current user  : $(whoami)"
    echo "Kernel        : $(uname -r)"
    echo "OS / Arch     : $(uname -s) $(uname -m)"
    echo "Date & time   : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Uptime        : $(uptime -p 2> /dev/null || uptime)"
    if [ -f /etc/os-release ]; then
        echo "Distribution  : $(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)"
    fi
}

cpu_memory() {
    header "CPU AND MEMORY"
    if [ -f /proc/cpuinfo ]; then
        echo "CPU model     : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
        echo "CPU cores     : $(grep -c '^processor' /proc/cpuinfo)"
    fi
    echo "Load average  : $(cut -d' ' -f1-3 /proc/loadavg 2> /dev/null)"
    echo
    if need_cmd free; then
        free -h
    fi
}

disk_usage() {
    header "DISK USAGE"
    df -h | head -n 1
    df -h | grep '^/dev/' | sort -k5 -r
    echo
    read -r -p "Enter a directory to measure (Enter = home): " dir
    dir=${dir:-$HOME}
    if [ ! -d "$dir" ]; then
        echo "Error: '$dir' is not a directory."
    elif [ ! -r "$dir" ]; then
        echo "Error: no read permission for '$dir'."
    else
        echo "Total size of $dir: $(du -sh "$dir" 2> /dev/null | cut -f1)"
        echo "Largest items inside:"
        du -sh "$dir"/* 2> /dev/null | sort -rh | head -n 5
    fi
}

top_processes() {
    header "TOP PROCESSES"
    read -r -p "How many processes to show? (1-50): " n
    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt 50 ]; then
        echo "Error: please enter a whole number from 1 to 50."
        return
    fi
    read -r -p "Sort by (c)pu or (m)emory? " sortby
    case "$sortby" in
        m|M) key="-%mem"; echo "Sorted by memory:" ;;
        *)   key="-%cpu"; echo "Sorted by CPU:" ;;
    esac
    ps -eo pid,user,%cpu,%mem,comm --sort="$key" | head -n $((n + 1))
    echo
    echo "Total running processes: $(ps -e --no-headers | wc -l)"
}

network_info() {
    header "NETWORK INFORMATION"
    if need_cmd ip; then
        echo "Interfaces and IP addresses:"
        ip -brief address
        echo
        echo "Default route:"
        ip route | grep default || echo "No default route found."
    else
        echo "IP address(es): $(hostname -I 2> /dev/null)"
    fi
    echo
    read -r -p "Ping a host to test connectivity? (leave blank to skip): " host
    if [ -n "$host" ]; then
        if ping -c 3 -W 2 "$host" > /dev/null 2>&1; then
            echo "$host is reachable."
        else
            echo "$host is NOT reachable (or ping is blocked)."
        fi
    fi
}

user_info() {
    header "USER INFORMATION"
    echo "Logged-in users:"
    who || echo "Cannot read login information."
    echo
    echo "Number of accounts in /etc/passwd: $(wc -l < /etc/passwd)"
    echo "Users with a login shell (bash/sh):"
    grep -E '(bash|sh)$' /etc/passwd | cut -d: -f1 | sort | tr '\n' ' '
    echo
}

search_files() {
    header "FILE SEARCH"
    read -r -p "Directory to search in: " dir
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        echo "Error: '$dir' is not a valid directory."
        return
    fi
    read -r -p "File name pattern (e.g. *.log): " pattern
    if [ -z "$pattern" ]; then
        echo "Error: pattern cannot be empty."
        return
    fi
    results=$(find "$dir" -type f -name "$pattern" 2> /dev/null)
    if [ -z "$results" ]; then
        echo "No files matching '$pattern' found in $dir."
    else
        count=$(echo "$results" | wc -l)
        echo "Found $count file(s). Showing up to 20:"
        echo "$results" | head -n 20 | while read -r f; do
            ls -lh "$f"
        done
    fi
}

save_report() {
    prepare_report_dir || return 1
    file="$REPORT_DIR/report_$(date '+%Y%m%d_%H%M%S').txt"
    {
        echo "System report created by $SCRIPT_NAME"
        system_overview
        cpu_memory
        header "DISK USAGE"
        df -h
        header "TOP 10 PROCESSES BY CPU"
        ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 11
        header "LOGGED-IN USERS"
        who
    } > "$file" 2> /dev/null

    if [ -s "$file" ]; then
        echo "Report saved to: $file ($(wc -l < "$file") lines)"
    else
        echo "Error: report could not be written."
        return 1
    fi
}

manage_reports() {
    header "SAVED REPORTS"
    if [ ! -d "$REPORT_DIR" ] || [ -z "$(ls -A "$REPORT_DIR" 2> /dev/null)" ]; then
        echo "No reports saved yet. Use option 8 first."
        return
    fi
    reports=("$REPORT_DIR"/*.txt)
    i=1
    for r in "${reports[@]}"; do
        echo "  $i) $(basename "$r")  [$(du -h "$r" | cut -f1)]"
        i=$((i + 1))
    done
    echo
    read -r -p "Report number: " num
    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#reports[@]}" ]; then
        echo "Error: invalid report number."
        return
    fi
    chosen="${reports[$((num - 1))]}"
    read -r -p "(v)iew or (d)elete $(basename "$chosen")? " action
    case "$action" in
        v|V) cat "$chosen" ;;
        d|D)
            read -r -p "Are you sure? (y/n): " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                rm -f "$chosen" && echo "Deleted."
            else
                echo "Cancelled."
            fi
            ;;
        *) echo "Error: unknown action." ;;
    esac
}

show_menu() {
    clear 2> /dev/null
    echo "$LINE"
    echo "        SYSTEM INFORMATION UTILITY"
    echo "        user: $(whoami)   host: $(hostname)"
    echo "$LINE"
    echo "  1) System overview"
    echo "  2) CPU and memory"
    echo "  3) Disk usage"
    echo "  4) Top processes"
    echo "  5) Network information"
    echo "  6) User information"
    echo "  7) Search for files"
    echo "  8) Save full report to file"
    echo "  9) View / delete saved reports"
    echo "  0) Exit"
    echo "$LINE"
}

while getopts ":d:rh" opt; do
    case "$opt" in
        d) REPORT_DIR="$OPTARG" ;;
        r) RUN_ONCE=1 ;;
        h) show_help; exit 0 ;;
        :) echo "Error: option -$OPTARG needs a value."; show_help; exit 1 ;;
        \?) echo "Error: unknown option -$OPTARG"; show_help; exit 1 ;;
    esac
done

if [ "$RUN_ONCE" -eq 1 ]; then
    save_report
    exit $?
fi

while true; do
    show_menu
    read -r -p "Choose an option [0-9]: " choice
    case "$choice" in
        1) system_overview ;;
        2) cpu_memory ;;
        3) disk_usage ;;
        4) top_processes ;;
        5) network_info ;;
        6) user_info ;;
        7) search_files ;;
        8) save_report ;;
        9) manage_reports ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo "Error: '$choice' is not a valid option. Enter 0-9." ;;
    esac
    pause
done
