#!/bin/bash


GRAFANA_BUILD=/usr/share/grafana/public/build

if [ ! -d $GRAFANA_BUILD ]; then
    echo "FAILED"
    exit 255
fi

cd $GRAFANA_BUILD

CHANGE=0

# Apply RGM theme
for file in $(grep Roboto * | cut -d':' -f1 | sort -u); do
    CHANGE=$(( $CHANGE +1 ))
    sed -i 's/Roboto/Fira Sans/g' $file
done

for file in $(grep 52545c * | cut -d':' -f1 | sort -u); do
    sed -i 's/#52545c/#337ab7/g' $file
    CHANGE=$(( $CHANGE +1 ))
done

for file in $(ls -1 *.css); do
    if [ "$(grep -c 'padding:6px 10px;color: #f7f8fa;font-weight:500;' $file)" != "0" ]; then
        sed -i 's/padding:6px 10px;color: #f7f8fa;font-weight:500;/padding:6px 10px;color: #767980;font-weight:500;/g' $file
        CHANGE=$(( $CHANGE +1 ))
    fi
    if [ "$(grep -c 'sidemenu{background:#1e2028;height:auto;box-shadow:5px 0 10px -5px #337ab7;position:relative;z-index:1025}' $file)" != "0" ]; then
        sed -i 's/sidemenu{background:#1e2028;height:auto;box-shadow:5px 0 10px -5px #337ab7;position:relative;z-index:1025}/sidemenu{background:#f8f8f8;height:auto;box-shadow:5px 0 10px -5px #f7f8fa;position:relative;z-index:1025}/g' $file
        CHANGE=$(( $CHANGE +1 ))
    fi
done

for file in $(ls -1 grafana.light.*.css); do
    if [ "$(grep -c 'font-face {font-family: Fira Sans;src' $file)" == "0" ]; then
        echo '@font-face {font-family: Fira Sans;src: url(/fonts/FiraSans-Regular.woff);}' >> $file
        CHANGE=$(( $CHANGE +1 ))
    fi
    if [ "$(grep -c 'a{color:#f8f8f8}' $file)" != "0" ]; then
        sed -i 's/a{color:#f8f8f8}/a{color:#767980}/g' $file
        CHANGE=$(( $CHANGE +1 ))
    fi
    if [ "$(grep -c 'btn-inverse{color:#f8f8f8;' $file)" != "0" ]; then
        sed -i 's/btn-inverse{color:#f8f8f8;/btn-inverse{color:#767980;/g' $file
        CHANGE=$(( $CHANGE +1 ))
    fi
done

for file in $(grep graph-legend-value * | cut -d':' -f1 | sort -u); do
    if [ "$(grep -c 'graph-legend-value{display:inline;cursor:pointer;white-space:nowrap;font-size:85%;text-align:left}' $file)" != "0" ]; then
    	sed -i 's/graph-legend-value{display:inline;cursor:pointer;white-space:nowrap;font-size:85%;text-align:left}/graph-legend-value{display:inline;cursor:pointer;white-space:nowrap;font-size:85%;text-align:left;color:#767980}/g' $file;
        CHANGE=$(( $CHANGE +1 ))
    fi
done

# Patch SVG icons with RGM theme
if [ "$(grep -c 'icons_dark_theme' grafana.light.8ec106c095469ac98ef1.css)" != "0" ]; then
    sed -i 's/icons_dark_theme/icons_light_theme/g' grafana.light.8ec106c095469ac98ef1.css
    CHANGE=$(( $CHANGE +1 ))
fi
if [ "$(grep -c '.icon-gf{color:#e9edf2;' grafana.light.8ec106c095469ac98ef1.css)" != "0" ]; then
    sed -i 's/.icon-gf{color:#e9edf2;/.icon-gf{/g' grafana.light.8ec106c095469ac98ef1.css
    CHANGE=$(( $CHANGE +1 ))
fi

echo "$CHANGE changes"
exit $CHANGE