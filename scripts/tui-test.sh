#!/bin/bash
# Fills terminal with blue background — transparency is immediately visible.
printf '\e[?25l\e[2J\e[H'
for r in $(seq 1 50); do
    printf '\e[44;37m'
    printf '%0.s ' $(seq 1 200)
    printf '\n'
done
printf '\e[12;10H\e[44;33mOPAQUE TEST: solid blue = OK, desktop visible = BUG\e[0m'
printf '\e[13;10H\e[41;37mRED BLOCK TEST                                      \e[0m'
printf '\e[14;10H\e[42;30mGREEN BLOCK TEST                                    \e[0m'
printf '\e[15;10H\e[46;30mCYAN BLOCK TEST                                     \e[0m'
read -r -s -n 1
printf '\e[?25h\e[0m\e[2J'
