#!/bin/sh
# Hook opt-in para responder AskUserQuestion desde la isla.
# Si algo falla, no imprime nada: Claude Code conserva su pregunta normal en la terminal.
[ -n "$CLAUDE_PET_REVIEW" ] && exit 0
[ "${1:-PreToolUse}" = "PreToolUse" ] || exit 0
PET_DIR="$HOME/.claude-pet"
SOCK="${CLAUDE_PET_ASK_SOCK:-$PET_DIR/ask.sock}"
[ -f "$PET_DIR/island-permissions" ] || exit 0
[ -S "$SOCK" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v perl >/dev/null 2>&1 || exit 0
input=$(head -c 262144 2>/dev/null); [ -n "$input" ] || exit 0
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$tool" = "AskUserQuestion" ] || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' | tr -cd 'A-Za-z0-9_-' | cut -c1-16)
proj=$(printf '%s' "$input" | jq -r '.cwd // ""' | sed 's#/$##; s#.*/##' | tr -cd 'A-Za-z0-9_.-' | cut -c1-40)
questions=$(printf '%s' "$input" | jq -c '.tool_input.questions // []' 2>/dev/null)
[ "$questions" != "[]" ] || exit 0
payload=$(printf '%s' "$questions" | base64 | tr -d '\n')
line=$(printf 'ask\t%s\t%s\t%s\n' "$sid" "$proj" "$payload")
export CLAUDE_PET_QUESTIONS="$questions"
exec perl -e '
use strict; use IO::Socket::UNIX;
my ($path,$wait,$line)=@ARGV; my $s=IO::Socket::UNIX->new(Peer=>$path) or exit 0;
$s->autoflush(1); print $s $line; $SIG{ALRM}=sub{exit 0}; alarm $wait;
my $r=<$s>; exit 0 unless defined $r; $r =~ s/^\s+|\s+$//g;
print "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\",\"updatedInput\":{\"questions\":$ENV{CLAUDE_PET_QUESTIONS},\"answers\":$r}}}\n" if $r =~ /^\{[^\n]*\}$/;
' "$SOCK" "${CLAUDE_PET_ASK_WAIT:-110}" "$line"
