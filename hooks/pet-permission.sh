#!/bin/sh
# Hook PermissionRequest: deja responder el permiso desde la isla de claude pet.
#
# Es opt-in y a prueba de fallos. No hace nada (sale con 0 y sin imprimir, asi que Claude Code pregunta en la
# terminal como siempre) salvo que TODO esto se cumpla:
#   - la app esta en modo isla y tienes activado "responder permisos desde la isla" (la app crea
#     ~/.claude-pet/island-permissions y lo borra al cambiar de modo o salir);
#   - existe el socket ~/.claude-pet/ask.sock y la app responde antes del plazo;
#   - hay jq y perl (los dos vienen con macOS o se instalan con brew).
# Privacidad: el comando o archivo que se va a aprobar viaja por un socket unix 0600 solo al mismo usuario,
# se muestra en la isla y no se guarda ni se publica en el pet bus.

[ -n "$CLAUDE_PET_REVIEW" ] && exit 0

PET_DIR="$HOME/.claude-pet"
SOCK="${CLAUDE_PET_ASK_SOCK:-$PET_DIR/ask.sock}"
WAIT="${CLAUDE_PET_ASK_WAIT:-110}"

[ -f "$PET_DIR/island-permissions" ] || exit 0
[ -S "$SOCK" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v perl >/dev/null 2>&1 || exit 0

input=$(head -c 262145 2>/dev/null)
[ -n "$input" ] || exit 0
[ "${#input}" -le 262144 ] || exit 0

flat() { tr -d '\000-\037\\' | head -c "$1"; }

sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' 2>/dev/null | flat 8)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null | flat 40)
[ -n "$tool" ] || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
proj=$(printf '%s' "${cwd##*/}" | tr -cd 'A-Za-z0-9_.-' | cut -c1-40)
# un plan (ExitPlanMode) trae su texto en .plan: se aplana a una linea y admite mas largo que un comando
lim=400; [ "$tool" = "ExitPlanMode" ] && lim=1500
detail=$(printf '%s' "$input" | jq -r '.tool_input | (.command // .file_path // .notebook_path // .url // .pattern // .path // ((.plan // "") | gsub("[\r\n]+"; " ~ ")))' 2>/dev/null | flat "$lim")
always=0
printf '%s' "$input" | jq -e '[.permission_suggestions[]? | select(.type == "addRules" and .behavior == "allow")] | length > 0' >/dev/null 2>&1 && always=1

ALLOW='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
DENY='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denegado desde claude pet."}}}'
# "siempre permitir" reutiliza la regla que Claude Code sugirio; sin regla equivale a permitir esta vez
ALWAYS=$(printf '%s' "$input" | jq -c '[.permission_suggestions[]? | select(.type == "addRules" and .behavior == "allow")][0] as $s
  | {hookSpecificOutput: {hookEventName: "PermissionRequest", decision: ({behavior: "allow"} + (if $s then {updatedPermissions: [$s]} else {} end))}}' 2>/dev/null)
[ -n "$ALWAYS" ] || ALWAYS="$ALLOW"

# Segundo mensaje: el cambio que pide Edit/MultiEdit/Write/NotebookEdit, el comando de Bash sin tocar y el cwd, como un
# unico json en una linea (jq escapa tabuladores, saltos y nulos, asi que ningun byte del contenido rompe el encuadre) y
# con el texto ya recortado por caracteres (nunca parte un utf-8). Si algo falla, no hay segundo mensaje y el permiso
# sale exactamente como antes. La app antigua descarta la marca (un caracter de control) y el resto de la conexion.
JQ_CHANGE='
  def cut($n): if length > $n then .[:$n] else . end;
  def part($n): (. // "" | tostring) as $s | ($s | cut(($n / $sc) | floor)) as $k
    | {t: $k, m: (($s | split("\n") | length) - ($k | split("\n") | length))};
  .tool_input as $i | .tool_name as $t
  | {cwd: ((.cwd // "") | tostring | cut(1024))}
  + (if $t == "Edit" then {k: "edit", p: ($i.file_path // ""), e: [{o: ($i.old_string | part(8000)), n: ($i.new_string | part(8000))}]}
     elif $t == "MultiEdit" then {k: "multi", p: ($i.file_path // ""), e: [($i.edits // [])[:20][] | {o: (.old_string | part(3000)), n: (.new_string | part(3000))}], x: ((($i.edits // []) | length) - 20 | if . > 0 then . else 0 end)}
     elif $t == "Write" then {k: "write", p: ($i.file_path // ""), c: ($i.content | part(40000))}
     elif $t == "NotebookEdit" then {k: "nb", p: ($i.notebook_path // ""), md: ($i.edit_mode // "replace"), c: ($i.new_source | part(16000))}
     elif $t == "Bash" then {k: "bash"} + (if (($i.command | type) == "string") and (($i.command | length) <= $cm) and (($i.command | length) > 0) then {cmd: $i.command} else {} end)
     else {k: "none"} end)'
diff=""
for try in "1 32768" "8 32768" "8 0"; do
  set -- $try
  diff=$(printf '%s' "$input" | jq -c --argjson sc "$1" --argjson cm "$2" "$JQ_CHANGE" 2>/dev/null)
  [ -n "$diff" ] || break
  [ "$(printf '%s' "$diff" | wc -c)" -le 131072 ] && break
  diff=""
done
marker=""; [ -n "$diff" ] && marker=$(printf '\037')

line=$(printf 'perm\t%s\t%s\t%s\t%s\t%s%s\n' "$sid" "$tool" "$proj" "$always" "$detail" "$marker")

# Se queda esperando la respuesta en la misma conexion. `exec` deja a perl como el proceso del hook: si Claude Code
# lo cierra (por ejemplo porque respondiste en la terminal) la conexion se cierra y la isla retira la tarjeta.
# Sin respuesta, error o plazo agotado no imprime nada y Claude Code pregunta en la terminal.
exec perl -e '
  use strict; use IO::Socket::UNIX;
  my ($path, $wait, $line, $allow, $always, $deny, $diff) = @ARGV;
  $SIG{PIPE} = "IGNORE";
  $SIG{ALRM} = sub { exit 0 };
  my $s = IO::Socket::UNIX->new(Peer => $path) or exit 0;
  $s->autoflush(1);
  alarm $wait;
  print $s $line, "\n";
  print $s "diff\t", length($diff), "\n", $diff if length($diff);
  my $r = <$s>;
  exit 0 unless defined $r;
  $r =~ s/\s+//g;
  print(($r eq "allow" ? $allow : $r eq "always" ? $always : $r eq "deny" ? $deny : ""), "\n") if $r =~ /^(allow|always|deny)$/;
  exit 0;
' "$SOCK" "$WAIT" "$line" "$ALLOW" "$ALWAYS" "$DENY" "$diff"
