# hakuke shell integration for zsh
# Auto-sourced when running inside hakuke terminal.
# Enables Shift+Arrow text selection in the command line.
#
# Based on zsh-shift-select by Jakub Jirutka (MIT License)
# https://github.com/jirutka/zsh-shift-select

# Only load in hakuke
[[ -n "$MACUAKE" ]] || return 0

# --- Shift-select mode ---

function end-of-buffer() {
	CURSOR=${#BUFFER}
	zle end-of-line -w
}
zle -N end-of-buffer

function beginning-of-buffer() {
	CURSOR=0
	zle beginning-of-line -w
}
zle -N beginning-of-buffer

function shift-select::kill-region() {
	zle kill-region -w
	zle -K main
}
zle -N shift-select::kill-region

function shift-select::deselect-and-input() {
	zle deactivate-region -w
	zle -K main
	zle -U "$KEYS"
}
zle -N shift-select::deselect-and-input

function shift-select::select-and-invoke() {
	if (( !REGION_ACTIVE )); then
		zle set-mark-command -w
		zle -K shift-select
	fi
	zle ${WIDGET#shift-select::} -w
}

function {
	emulate -L zsh

	bindkey -N shift-select
	bindkey -M shift-select -R '^@'-'^?' shift-select::deselect-and-input

	local kcap seq seq_mac widget

	for	kcap   seq          seq_mac    widget (
		kLFT   '^[[1;2D'    x          backward-char        # Shift + Left
		kRIT   '^[[1;2C'    x          forward-char         # Shift + Right
		kri    '^[[1;2A'    x          up-line              # Shift + Up
		kind   '^[[1;2B'    x          down-line            # Shift + Down
		kHOM   '^[[1;2H'    x          beginning-of-line    # Shift + Home
		kEND   '^[[1;2F'    x          end-of-line          # Shift + End
		x      '^[[1;6D'    '^[[1;4D'  backward-word        # Shift + Ctrl/Option + Left
		x      '^[[1;6C'    '^[[1;4C'  forward-word         # Shift + Ctrl/Option + Right
		x      '^[[1;6H'    '^[[1;4H'  beginning-of-buffer  # Shift + Ctrl/Option + Home
		x      '^[[1;6F'    '^[[1;4F'  end-of-buffer        # Shift + Ctrl/Option + End
	); do
		[[ "$OSTYPE" = darwin* && "$seq_mac" != x ]] && seq=$seq_mac
		zle -N shift-select::$widget shift-select::select-and-invoke
		bindkey -M emacs ${terminfo[$kcap]:-$seq} shift-select::$widget
		bindkey -M shift-select ${terminfo[$kcap]:-$seq} shift-select::$widget
	done

	for	kcap   seq        widget (
		kdch1  '^[[3~'    shift-select::kill-region         # Delete
		bs     '^?'       shift-select::kill-region         # Backspace
	); do
		bindkey -M shift-select ${terminfo[$kcap]:-$seq} $widget
	done
}
