#!/bin/bash
set -e

ORIG_IMAGE="$1"
NATURE_M_IN_PIXEL="6.54"
SCALE=50000 # Nature meters in map meter
SHEET_AVAILABLE_WIDTH_MM=200
SHEET_AVAILABLE_HEIGHT_MM=287
GRID_STEP_M=1000
GRID_THICKNESS=1

DST_IMAGE="${ORIG_IMAGE}__scale_${SCALE}__gridstep_${GRID_STEP_M}"
FILTERED_IMAGE="${DST_IMAGE}.png"
FILTERED_PIECES_PRE_WILDCARD="${DST_IMAGE}__pieces_"
FILTERED_PIECES=$FILTERED_PIECES_PRE_WILDCARD"%02d.png"

# Get image dimensions
PROPERTIES=`mktemp`
ffprobe -print_format ini -show_format -show_streams "$ORIG_IMAGE" 2>/dev/null | egrep 'width|height' > $PROPERTIES
.  $PROPERTIES
rm $PROPERTIES
export ORIG_WIDTH=$width
export ORIG_HEIGHT=$height

# Get map dimensions
MAP_PIXELS_IN_M=`echo "scale=4; $SCALE / $NATURE_M_IN_PIXEL" | bc` # This many pixels of map get printed on 1 meter of paper
echo "Must place $MAP_PIXELS_IN_M map pixels on 1 meter of paper"
MAP_PIXELS_IN_M_ROUNDED=`echo "$MAP_PIXELS_IN_M/1" | bc`
MAP_DPI=`echo "scale=4; $MAP_PIXELS_IN_M * 2.54 / 100" | bc` # How many dots-per-inch to set for printing
MAP_DPI=`echo "($MAP_DPI+0.5)/1" | bc`
echo "Map must be printed at resolution $MAP_DPI dpi ($MAP_PIXELS_IN_M_ROUNDED pixels per meter)"

echo "Map is $ORIG_WIDTH pixel width, $ORIG_HEIGHT pixel height"
MAP_PAPER_WIDTH_MM=$(( 1000 * ORIG_WIDTH / MAP_PIXELS_IN_M_ROUNDED ))
MAP_PAPER_HEIGHT_MM=$(( 1000 * ORIG_HEIGHT / MAP_PIXELS_IN_M_ROUNDED ))
echo "This is $MAP_PAPER_WIDTH_MM by $MAP_PAPER_HEIGHT_MM mm"
export GRID_STEP=$(( GRID_STEP_M * MAP_PIXELS_IN_M_ROUNDED / SCALE ))
echo "Grid step of $GRID_STEP_M meters is $GRID_STEP pixels"
  
MAX_PIXELS_ON_SHEET_WIDTH=$(( MAP_PIXELS_IN_M_ROUNDED * SHEET_AVAILABLE_WIDTH_MM / 1000 ))
MAX_PIXELS_ON_SHEET_HEIGHT=$(( MAP_PIXELS_IN_M_ROUNDED * SHEET_AVAILABLE_HEIGHT_MM / 1000 ))

count_sheets() {
  MAX_PIXELS_ON_SHEET_WIDTH=$1
  MAX_PIXELS_ON_SHEET_HEIGHT=$2
  SHEET_W=$(( GRID_STEP * (MAX_PIXELS_ON_SHEET_WIDTH / GRID_STEP)  ))
  SHEET_H=$(( GRID_STEP * (MAX_PIXELS_ON_SHEET_HEIGHT / GRID_STEP) ))
  N_SHEETS_W=$(( ORIG_WIDTH  / SHEET_W ))
  if [[ $(( N_SHEETS_W * SHEET_W )) -lt $ORIG_WIDTH ]]
  then
      N_SHEETS_W=$(( N_SHEETS_W + 1 ))
  fi
  N_SHEETS_H=$(( ORIG_HEIGHT / SHEET_H ))
  if [[ $(( N_SHEETS_H * SHEET_H )) -lt $ORIG_HEIGHT ]]
  then
      N_SHEETS_H=$(( N_SHEETS_H + 1 ))
  fi
  N_RESULT_SHEETS=$(( N_SHEETS_W * N_SHEETS_H ))
  echo $N_RESULT_SHEETS
}

N_SHEETS_PORTRAIT=`count_sheets $MAX_PIXELS_ON_SHEET_WIDTH $MAX_PIXELS_ON_SHEET_HEIGHT`
N_SHEETS_LANDSCAPE=`count_sheets $MAX_PIXELS_ON_SHEET_HEIGHT $MAX_PIXELS_ON_SHEET_WIDTH`
echo "Need $N_SHEETS_PORTRAIT portrait-oriented sheets, or $N_SHEETS_LANDSCAPE landscape-oriented"
if [[ $N_SHEETS_LANDSCAPE -lt $N_SHEETS_PORTRAIT ]]
then
  ORIENTATION="landscape"
  TMP=$MAX_PIXELS_ON_SHEET_WIDTH
  MAX_PIXELS_ON_SHEET_WIDTH=$MAX_PIXELS_ON_SHEET_HEIGHT
  MAX_PIXELS_ON_SHEET_HEIGHT=$TMP
  TMP=$SHEET_AVAILABLE_WIDTH_MM
  SHEET_AVAILABLE_WIDTH_MM=$SHEET_AVAILABLE_HEIGHT_MM
  SHEET_AVAILABLE_HEIGHT_MM=$SHEET_AVAILABLE_WIDTH_MM
else
  ORIENTATION="portrait"
fi
echo "Using $ORIENTATION orientation"

SHEET_W=$(( GRID_STEP * (MAX_PIXELS_ON_SHEET_WIDTH / GRID_STEP)  ))
SHEET_H=$(( GRID_STEP * (MAX_PIXELS_ON_SHEET_HEIGHT / GRID_STEP) ))
echo "Using $SHEET_W pixels of width on each sheet"
echo "Using $SHEET_H pixels of height on each sheet"

N_SHEETS_W=$(( ORIG_WIDTH  / SHEET_W ))
if [[ $(( N_SHEETS_W * SHEET_W )) -lt $ORIG_WIDTH ]]
then
    N_SHEETS_W=$(( N_SHEETS_W + 1 ))
fi
N_SHEETS_H=$(( ORIG_HEIGHT / SHEET_H ))
if [[ $(( N_SHEETS_H * SHEET_H )) -lt $ORIG_HEIGHT ]]
then
    N_SHEETS_H=$(( N_SHEETS_H + 1 ))
fi
N_RESULT_SHEETS=$(( N_SHEETS_W * N_SHEETS_H ))

echo "Using $N_SHEETS_W sheets in width, $N_SHEETS_H in height, $N_RESULT_SHEETS total"

PAPER_WASTE_WIDTH_MM=$(( SHEET_AVAILABLE_WIDTH_MM * N_SHEETS_W - MAP_PAPER_WIDTH_MM ))
PAPER_WASTE_HEIGHT_MM=$(( SHEET_AVAILABLE_HEIGHT_MM * N_SHEETS_H - MAP_PAPER_HEIGHT_MM ))
echo "Wasting $PAPER_WASTE_WIDTH_MM mm of paper in width, $PAPER_WASTE_HEIGHT_MM in height"

ffmpeg -i "$ORIG_IMAGE" -vf "drawgrid=h=${GRID_STEP}:w=${GRID_STEP}:color=white:thickness=${GRID_THICKNESS},pad=color=white:width=$(( N_SHEETS_W * SHEET_W )):height=$(( N_SHEETS_H * SHEET_H ))" "$FILTERED_IMAGE" -y

ffmpeg -loglevel debug -loop 1 -i "$FILTERED_IMAGE" -frames $N_RESULT_SHEETS -vf "crop=out_w=${SHEET_W}:out_h=${SHEET_H}:x=out_w*mod(n\\,${N_SHEETS_W}):y=out_h*floor(n/${N_SHEETS_W})" -dpm $MAP_PIXELS_IN_M_ROUNDED "$FILTERED_PIECES" -y 

echo "Now print pieces with command:"
echo -n "lp "
if [[ $ORIENTATION == "landscape" ]]
then
  echo -n "-o landscape "
fi
echo $FILTERED_PIECES_PRE_WILDCARD'*'
