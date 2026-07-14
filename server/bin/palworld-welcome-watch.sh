#!/usr/bin/env bash
set -euo pipefail

API_BIN="/srv/storage/steam/bin/palworld-api.sh"
ANNOUNCE_BIN="/srv/storage/steam/bin/palworld-announce.sh"
STATE_DIR="/srv/storage/steam/servers/palworld/state"
KNOWN_FILE="$STATE_DIR/welcome-known-players.txt"
ANNOUNCED_FILE="$STATE_DIR/welcome-announced.tsv"
INTERVAL_SECONDS="${PALWORLD_WELCOME_INTERVAL:-15}"
MIN_GAP_SECONDS="${PALWORLD_WELCOME_MIN_GAP_SECONDS:-1800}"

messages=(
  "Bienvenue, {player}. Que les Pals te craignent."
  "Alerte base: {player} vient d'arriver. Cachez les Chikipis."
  "{player} rejoint l'expédition. Objectif: survivre avec style."
  "Bienvenue {player}. Loot propre, captures sales, bonne chasse."
  "{player} entre dans Palpagos. Les boss n'ont qu'à bien se tenir."
  "{player} est en ligne. La faune locale demande un avocat."
  "Attention: {player} a retrouvé le chemin du serveur."
  "{player} débarque. Quelqu'un a pensé à cacher les ressources rares?"
  "Bienvenue {player}. Ici, même les moutons ont des intentions."
  "{player} rejoint l'aventure. La sécurité décline toute responsabilité."
  "Les portes s'ouvrent pour {player}. Les ennuis aussi."
  "{player} est arrivé. Le taux de survie vient de devenir une statistique."
  "Bienvenue {player}. Le plan est simple: improviser très fort."
  "{player} rejoint Palpagos. Merci de ne pas nourrir les boss."
  "Alerte météo: forte probabilité de chaos autour de {player}."
  "{player} vient d'apparaître. Les coffres se sentent déjà moins pleins."
  "Bienvenue {player}. La carte est grande, les mauvaises idées aussi."
  "{player} est là. Le comité d'accueil a été mangé par un Pal."
  "Palpagos accueille {player}. Aucun remboursement après la première capture."
  "{player} vient de se connecter. Les Chikipis font semblant de ne pas paniquer."
  "Bienvenue {player}. Capture d'abord, pose les questions beaucoup plus tard."
  "{player} entre en scène. La discrétion n'était visiblement pas au programme."
  "Bonne chasse, {player}. Essaie de revenir avec le même nombre de membres."
  "{player} rejoint l'équipe. Notre assurance vient encore d'augmenter."
  "Bienvenue {player}. Les Pals sauvages ont reçu ta photo."
  "{player} est de retour. Les murs de la base tremblent déjà."
  "Alerte inventaire: {player} approche avec des besoins très raisonnables."
  "{player} arrive sur Palpagos. La productivité vient officiellement de chuter."
  "Bienvenue {player}. Aujourd'hui, nous testons la notion de conséquences."
  "{player} vient d'entrer. Le bouton rouge est purement décoratif, probablement."
  "Les boss ont été informés de l'arrivée de {player}. Ils ont ri."
  "{player} est connecté. Quelqu'un surveille la réserve de munitions?"
  "Bienvenue {player}. Ton lit est prêt, contrairement au reste de la base."
  "{player} rejoint l'expédition. Niveau de préparation: enthousiaste."
  "Palpagos signale l'arrivée de {player}. La paix aura été brève."
  "{player} vient de revenir. On avait pourtant presque tout réparé."
  "Bienvenue {player}. Les coffres sont étiquetés; ça ne changera rien."
  "{player} est arrivé. Merci de laisser au moins un arbre debout."
  "Alerte générale: {player} a une idée. Éloignez les matériaux précieux."
  "Bienvenue {player}. Si ça brille, c'est rare, dangereux ou les deux."
  "{player} entre dans la partie. Les plans prudents peuvent maintenant être rangés."
  "Un nouveau chapitre commence avec {player}. Il sera probablement coûteux."
  "{player} rejoint le serveur. Les Pals de travail réclament déjà une pause."
  "Bienvenue {player}. La survie est obligatoire; l'élégance est facultative."
  "{player} est en ligne. La base vient de perdre sa garantie."
  "Palpagos accueille {player}. Les réparations seront facturées à la guilde."
  "{player} vient d'arriver. Le danger était déjà là, mais maintenant il a un ami."
  "Bienvenue {player}. Essaie de ne pas apprivoiser quelque chose qui te mange."
  "{player} rejoint l'aventure. Les décisions douteuses peuvent reprendre."
  "Alerte Paldeck: {player} cherche encore ce qui manque à sa collection."
  "{player} est de retour. Les marchands cachent leurs meilleures offres."
  "Bienvenue {player}. Aujourd'hui est un excellent jour pour manquer de sphères."
  "{player} arrive. Les ressources communes deviennent soudainement stratégiques."
  "Palpagos vient de charger {player}. Le chaos peut commencer."
  "{player} rejoint la partie. Merci de garder les explosions vaguement contrôlées."
  "Bienvenue {player}. Le trajet était long, les boss seront plus longs."
  "{player} est là. La réserve de nourriture demande une protection rapprochée."
  "Alerte exploration: {player} s'apprête à ignorer tous les panneaux de danger."
  "Bienvenue {player}. Une sphère vide est une occasion ratée."
  "{player} rejoint Palpagos. Les Pals légendaires ont coupé leur téléphone."
  "{player} vient d'apparaître. Le serveur respire profondément."
  "Bienvenue {player}. Ta mission: revenir avec du loot et une histoire crédible."
  "{player} est connecté. La stratégie sera annoncée après la catastrophe."
  "Palpagos ouvre ses portes à {player}. Elles ferment mal, soit dit en passant."
  "{player} rejoint l'équipe. Compétence spéciale détectée: confiance injustifiée."
  "Bienvenue {player}. Chaque grande base commence par un coffre mal placé."
  "{player} est de retour. Les Pals assignés au travail soupirent en cadence."
  "Alerte boss: {player} vient chercher une victoire parfaitement méritée, sûrement."
  "Bienvenue {player}. Ne cours pas plus vite que le danger, juste que tes amis."
  "{player} arrive. Les plans de construction deviennent des suggestions."
  "Palpagos accueille {player}. Attention aux falaises et aux décisions spontanées."
  "{player} est en ligne. Le prochain incident portera probablement son nom."
  "Bienvenue {player}. Nous avions du calme, mais c'était surfait."
  "{player} rejoint l'aventure. Les coffres pleins sont un mythe collectif."
  "Alerte capture: {player} a encore dit juste une dernière."
  "Bienvenue {player}. Les chances sont bonnes; les probabilités, moins."
  "{player} débarque. Le conseil de survie du jour: évite de mourir."
  "Palpagos confirme l'arrivée de {player}. Aucun Pal n'a souhaité commenter."
  "{player} rejoint la partie. Les réparations d'hier étaient donc temporaires."
  "Bienvenue {player}. Les grandes aventures commencent souvent sans assez de munitions."
  "{player} est là. Le plan B demande déjà où est le plan C."
  "Alerte guilde: {player} vient apporter son expertise très expérimentale."
  "Bienvenue {player}. Ici, le danger est gratuit et le loot ne l'est pas."
  "{player} entre dans Palpagos. Les statues de puissance se sentent observées."
  "{player} vient de se connecter. C'est officiellement le problème des boss."
  "Bienvenue {player}. Que tes captures soient critiques et tes chutes non mortelles."
  "Palpagos reçoit {player}. Les réserves de bois ne survivront pas à la soirée."
  "{player} est arrivé. On lance les dés et on appelle ça une stratégie."
  "Bienvenue {player}. Ton équipement est prêt à être perdu avec panache."
  "{player} rejoint le serveur. Les Pals nocturnes annulent leur sieste."
  "Alerte aventure: {player} vient tester les limites du bon sens."
  "Bienvenue {player}. Les raccourcis sont rapides jusqu'à la première falaise."
  "{player} est de retour. Le calme dépose officiellement sa démission."
)

list_players() {
  "$API_BIN" GET /players | jq -r '.players[]?.name // empty' | LC_ALL=C sort -u
}

sort_players_file() {
  local file="$1"
  local tmp_file

  tmp_file="$(mktemp)"
  LC_ALL=C sort -u "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

mkdir -p "$STATE_DIR"
touch "$KNOWN_FILE" "$ANNOUNCED_FILE"
sort_players_file "$KNOWN_FILE"

last_message_index() {
  local player="$1"

  awk -F '\t' -v player="$player" '$1 == player { value = $3 } END { print value }' "$ANNOUNCED_FILE"
}

choose_message_index() {
  local player="$1"
  local message_count="${#messages[@]}"
  local previous_index
  local index

  previous_index="$(last_message_index "$player")"
  index=$((RANDOM % message_count))

  # Keep every choice random while preventing an immediate repeat for a player.
  if [[ "$previous_index" =~ ^[0-9]+$ ]] && [ "$message_count" -gt 1 ] && [ "$index" -eq "$previous_index" ]; then
    index=$(((index + 1 + RANDOM % (message_count - 1)) % message_count))
  fi

  printf '%s' "$index"
}

render_message() {
  local player="$1"
  local index="$2"
  local template="${messages[$index]}"

  printf '%s' "${template//\{player\}/$player}"
}

last_announced_at() {
  local player="$1"

  awk -F '\t' -v player="$player" '$1 == player { value = $2 } END { print value }' "$ANNOUNCED_FILE"
}

record_announcement() {
  local player="$1"
  local now="$2"
  local message_index="$3"
  local tmp_file

  tmp_file="$(mktemp)"
  awk -F '\t' -v player="$player" '$1 != player' "$ANNOUNCED_FILE" > "$tmp_file"
  printf '%s\t%s\t%s\n' "$player" "$now" "$message_index" >> "$tmp_file"
  mv "$tmp_file" "$ANNOUNCED_FILE"
}

announce_player() {
  local player="$1"
  local now="$2"
  local last_at
  local message
  local message_index
  local encoded

  last_at="$(last_announced_at "$player")"
  if [ -n "$last_at" ] && [ "$last_at" -eq "$last_at" ] 2>/dev/null; then
    if [ $((now - last_at)) -lt "$MIN_GAP_SECONDS" ]; then
      return 0
    fi
  fi

  message_index="$(choose_message_index "$player")"
  message="$(render_message "$player" "$message_index")"
  encoded="$(printf '%s' "$message" | base64 -w 0)"

  "$ANNOUNCE_BIN" --base64 "$encoded" >/dev/null
  record_announcement "$player" "$now" "$message_index"
  printf 'Announced welcome message %s for %s\n' "$message_index" "$player"
}

if list_players > "$KNOWN_FILE.tmp"; then
  sort_players_file "$KNOWN_FILE.tmp"
  mv "$KNOWN_FILE.tmp" "$KNOWN_FILE"
else
  rm -f "$KNOWN_FILE.tmp"
  printf 'Could not read initial player list. Will retry.\n' >&2
fi

while true; do
  current_file="$(mktemp)"

  if list_players > "$current_file"; then
    sort_players_file "$KNOWN_FILE"
    sort_players_file "$current_file"
    now="$(date +%s)"
    while IFS= read -r player; do
      [ -n "$player" ] || continue
      announce_player "$player" "$now" || true
    done < <(comm -13 "$KNOWN_FILE" "$current_file")

    mv "$current_file" "$KNOWN_FILE"
  else
    rm -f "$current_file"
    printf 'Could not read player list. Waiting before retry.\n' >&2
  fi

  sleep "$INTERVAL_SECONDS"
done
