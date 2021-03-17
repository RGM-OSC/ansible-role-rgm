#!/bin/bash

DASHNAME=
DEFAULT=0
IDUSER=0

print_help() {
    cat <<EOF

$(basename $0) : set starred/default grafana dashboards

usage:
  $(basename $0) -b <dashboard title>' [ -d ] [ -u <used_id> ]

parameters:
  -b : dashboard title eg. 'Multi System Metrics'
  -d : set as default dashboard for user
  -u : user Id (default to uid 0 - admin user)

EOF
}

while getopts u:b:d arg; do
    case "$arg" in
        h) print_help ;;
        u) IDUSER="$OPTARG" ;;
        b) DASHNAME="$OPTARG" ;;
        d) DEFAULT=1 ;;
        *) print_help ;;
    esac
done

if [ -z "$DASHNAME" ]; then
    echo "Error: no dashboard Name provided"
    exit 1
fi

IDDASH="$(mysql --skip-column-names --batch grafana -e "SELECT id FROM dashboard WHERE title = '$DASHNAME'")"
if [ -e "$IDDASH" ]; then
    echo "Error: Unable to retrieve dashboard '$DASHNAME' in database"
    exit 1
fi

IDSTAR="$(mysql --skip-column-names --batch grafana -e "SELECT id FROM star WHERE user_id=1 AND dashboard_id=$IDDASH")"
if [ -z "$IDSTAR" ]; then
    mysql grafana -e "INSERT INTO star (user_id, dashboard_id) VALUES (1, $IDDASH)"
fi

if [ $DEFAULT -ne 0 ]; then
    IDPREF="$(mysql --skip-column-names --batch grafana -e "select id FROM preferences WHERE org_id=1 AND user_id=$IDUSER")"
    if [ -z "$IDPREF" ]; then
        mysql grafana -e "INSERT INTO preferences (org_id,user_id,home_dashboard_id,created,updated,team_id) VALUES (1, $IDUSER, $IDDASH, now(), now(), 0)"
    else
        mysql grafana -e "INSERT INTO preferences SET home_dashboard_id=$IDDASH WHERE id=$IDPREF"
    fi
fi