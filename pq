#!/bin/sh

# platformio quick

init_at=
speed=
devs=
dev=
env=
tty_only=
build_only=

SPEEDS='115200
9600
300
600
1200
2400
4800
14400
19200
38400
57600
230400
460800'

G='\033[1m\033[32m' # green
Y='\033[1m\033[33m' # yellow
B='\033[1m\033[34m' # blue
C='\033[1m\033[36m' # cyan
E='\033[1m\033[31m' # red
R='\033[0m'         # reset

info() {
    printf "${B}INFO:${R} %s\n" "$@"
}

ask() {
    printf "${Y}QUESTION:${R} %s\n" "$@"
}

ans() {
    printf "${C}ANSWER:${R} %s\n" "$@"
}

err() {
    printf "${E}ERROR:${R} %s\n" "$@" >&2
}

exists() {
    command -v "$1" >/dev/null
}

menu() {
    items=$(echo "$1" | sed 's/\\n/\n/g' | grep .)
    shift
    if exists fzf; then
        height=$(echo "$items" | wc -l)
        height=$((height + 2))
        echo "$items" | fzf --height "$height" "$@"
    else
        numbered=$(echo "$items" | nl)
        echo "$numbered" >/dev/tty
        read -r ans </dev/tty
        echo "$numbered" | sed -rn "s/^\s*$ans\s\s*(.+)/\1/p"
    fi
}

ask_menu() {
    q="$1"
    i="$2"
    shift 2
    ask "$q" >/dev/tty
    a=$(menu "$i" "$@")
    if [ -n "$a" ]; then
        ans "$a" >/dev/tty
        echo "$a"
    else
        ans "Skipped" >/dev/tty
        return 1
    fi
}

show_cmd() {
    printf "${G}\$${R} %s\n" "$*"
}

run() {
    show_cmd "$@"
    "$@"
}

run_ask() {
    show_cmd "$@"
    c=$(ask_menu 'Run the command above?' 'Yes\nNo')
    if [ "$c" = Yes ]; then
        "$@"
    else
        return 1
    fi
}

usage() {
    bin=$(basename "$0")
    echo "usage $bin [OPTION]..."
    echo '  -i=PATH    init a new project'
    echo '  -p=DEV     port'
    echo '  -s=SPEED   baud rate'
    echo '  -e=ENV     pio environment'
    echo '  -t         tty only'
    echo '  -b         build only'
    echo '  -h         show this help'
}

parse_args() {
    while getopts ':i:p:s:e:tbh' arg; do
        case ${arg} in
            i) init_at="${OPTARG}"  ;;
            t) tty_only=1           ;;
            b) build_only=1         ;;
            p) dev="${OPTARG}"      ;;
            s) speed="${OPTARG}"    ;;
            e) env="${OPTARG}"      ;;
            *) usage; return 1      ;;
        esac
    done
}

init() {
    path=${1-.}
    mkdir -p "$path/src"

    {
        echo '[env:esp32dev]'
        echo 'platform = espressif32'
        echo 'board = esp32dev'
        echo 'framework = arduino'
        echo
        echo '[env:nodemcuv2]'
        echo 'platform = espressif8266'
        echo 'board = nodemcuv2'
        echo 'framework = arduino'
        echo
        echo '[env:uno]'
        echo 'platform = atmelavr'
        echo 'board = uno'
        echo 'framework = arduino'

    } >"$path/platformio.ini"

    {
        echo '#include <Arduino.h>'
        echo
        echo '#define LED 2 // LED_BUILTIN'
        echo
        echo 'void setup() {'
        echo '    pinMode(LED, OUTPUT);'
        echo '}'
        echo
        echo 'void loop() {'
        echo '    digitalWrite(LED, HIGH);'
        echo '    delay(500);'
        echo '    digitalWrite(LED, LOW);'
        echo '    delay(500);'
        echo '}'
    } > "$path/src/main.cpp"
}

start_serial() {
    while :; do
        if exists pyserial-miniterm; then
            info 'Stop with C-]'
            run pyserial-miniterm "$dev" "$speed" --raw
        elif exists picocom; then
            info 'Stop with C-a C-x and then C-c'
            run picocom -b "$speed" "$dev"
        elif exists cu; then
            info 'Stop with ESC Enter ~ .'
            run cu -l "$dev" -s "$speed"
        else
            err 'No serial monitor utility found'
            return 1
        fi
        info 'Now C-c to stop'
        sleep 1
    done
}

set_dev() {
    if [ -n "$dev" ]; then
        if ! echo "$devs" | grep -q "$dev"; then
            err "Device '$dev' is not found"
            return 1
        fi
    else
        devs_len=$(echo "$devs" | wc -l)
        if [ -n "$devs" ] && [ "$devs_len" -gt 1 ]; then
            dev=$(ask_menu 'Select device' "$devs")
            [ -n "$dev" ] || return 1
        else
            dev="$devs"
        fi
    fi
}

set_env() {
    if [ -z "$env" ] && [ -f ./platformio.ini ]; then
        envs=$(sed -rn 's/\[env:(.+)\]/\1/p' ./platformio.ini)
        envs_len=$(echo "$envs" | wc -l)
        if [ -n "$envs" ] && [ "$envs_len" -gt 1 ]; then
            env=$(ask_menu 'Select build environment:' "$envs")
            [ -n "$env" ] || return 1
        else
            env="$envs"
        fi
    fi
}

set_speed() {
    if [ "$speed" = s ] || [ -z "$speed" ]; then
        # check platform.ini file
        if [ -f ./platformio.ini ]; then
            ini_speed=$(sed -rn 's/monitor_speed *= *(.+)/\1/p' ./platformio.ini)
            if echo "$SPEEDS" | grep -q "$ini_speed"; then
                # is a valid baud rate
                speed="$ini_speed"
                [ -n "$speed" ] &&
                    info "Setting speed to $speed from ./platformio.ini"
            fi
        fi

        # check source file(s)
        if [ -z "$speed" ] && [ -d ./src ]; then
            src_speed=$(cd ./src && grep -r 'Serial\.begin('           |
                                sed -rn 's/.*Serial\.begin\((.+)\).*/\1/p' |
                                uniq)
            # be sure there is only one speed
            src_speeds_count=$(echo "$src_speed" | wc -l)
            if [ "$src_speeds_count" = 1 ] &&
                   echo "$SPEEDS" | grep -q "$src_speed"; then
                speed="$src_speed"
                [ -n "$speed" ] &&
                    info "Setting speed to $speed from source file(s)"
            fi
        fi
    fi

    if [ -z "$speed" ]; then
        # don't know what to do; ask user
        speed=$(ask_menu 'Select serial tty baud rate:' "$SPEEDS")
        [ -n "$speed" ] || return 1
    fi
}

main() {
    parse_args "$@" || return

    # possible options
    options='New project\n'
    [ -f ./platformio.ini ] && options="${options}Build\n"
    devs=$(find /dev/ -maxdepth 1 -name 'ttyACM*' -or -name 'ttyUSB*' |
               sort -nr)
    if [ -n "$devs" ]; then
        [ -n "$devs" ] && options="${options}Serial TTY\n"
        [ -f ./platformio.ini ] && [ -n "$devs" ] && options="${options}Upload\n"
    fi

    # args option, if any
    if [ -n "$init_at" ]; then
        option='New project'
    elif [ -n "$tty_only" ]; then
        option='Serial TTY'
    elif [ -n "$build_only" ]; then
        option='Build'
    else
        option=
    fi

    # check options
    if [ -n "$option" ]; then
        if ! echo "$options" | grep -q "$option"; then
            err "$option is currently not possible"
            return 1
        fi
    else
        option=$(ask_menu 'What to do?' "$options" --tac)
    fi

    # run
    case "$option" in
        'New project')
            if [ -z "$init_at" ]; then
                ask 'Select project path:'
                read -r init_at
            fi
            [ -n "$init_at" ] || {
                err "Path can't be empty"
                return 1
            }
            init "$init_at" ;;

        'Build')
            set_env &&
                run pio run -e "$env" ;;

        'Serial TTY')
            set_dev && set_speed &&
                start_serial ;;

        'Upload')
            set_env && set_dev && set_speed &&
                run_ask pio run -t upload -e "$env" --upload-port "$dev" &&
                start_serial ;;

        '')
            return 1 ;;

        *)
            err "Unknown option '$option'"
            return 1
    esac
}

main "$@"
