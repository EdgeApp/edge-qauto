#!/bin/zsh
setopt null_glob

# Set iteration count
iterationCount=8

# Prepare test type for folder name: convert dashes to spaces and capitalize each word
raw_test_type="$(echo $MAESTRO_CMD | grep -oE 'performance/[^ ]+\.yaml' | sed -E 's/performance\/(.*)\.yaml/\1/')"
test_type_folder=$(echo "$raw_test_type" | sed 's/-/ /g')  # Convert dashes to spaces
test_type_folder_capitalized=$(echo "$test_type_folder" | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1')
run_date=$(date +%Y-%m-%d_%H-%M-%S)
series_folder="results/${test_type_folder_capitalized} ${run_date}"
mkdir -p "$series_folder"

# Keep a clean version (no spaces) for other uses
test_type_clean=$(echo "$raw_test_type" | tr -d '-')

# Find all files in builds-stagelist
build_files=(builds-stagelist/*)

if [[ ${#build_files[@]} -eq 0 ]]; then
  echo "No files found in builds-stagelist/"
  exit 1
fi

for build_file in "${build_files[@]}"; do
  if [[ ! -f "$build_file" ]]; then
    echo "No files found in builds-stagelist/"
    exit 1
  fi
  # Extract base name without extension, keep spaces
  build_name=$(basename "$build_file")
  build_name_noext="${build_name%.*}"
  # Remove 'App ' prefix if present
  build_name_noapp=$(echo "$build_name_noext" | sed 's/^App //')
  echo "\nInstalling $build_name_noext..."
  if ! adb install -r "$build_file"; then
    echo "Warning: Failed to install $build_name_noext, skipping tests for this build"
    continue
  fi

  resultsFilePath="${series_folder}/${build_name_noapp}.json"

  echo "Running test $raw_test_type on $build_name_noext..."
  set -e
  cmd="flashlight test --bundleId '$MAESTRO_APP_ID' \
    --testCommand '$MAESTRO_CMD' \
    ${MAESTRO_BEFORE_CMD:+--beforeEachCommand '$MAESTRO_BEFORE_CMD'} \
    ${MAESURE_DURATION:+--duration '$MAESURE_DURATION'} \
    --resultsFilePath '$resultsFilePath' \
    --iterationCount '$iterationCount';"
  eval $cmd
  set +e
  echo "Results saved to $resultsFilePath"

  # Generate HTML report and extract score
  flashlight report "$resultsFilePath"

  # HACK: Flashlight generates the report at a specific location in the temp directory
  # We look for the score in the generated HTML file
  reportPath="${TMPDIR}report_files/report.html"
  if [[ -f "$reportPath" ]]; then
    # Extract the score from the static HTML - this will work since the score is embedded in the HTML
    score=$(grep -oE 'aria-label="Score"[^>]*>[0-9]{2,3}' "$reportPath" | grep -oE '[0-9]{2,3}')
    
    if [[ -n "$score" ]]; then
      echo "Extracted score: $score"
      # Extract build number from build_name_noapp (assumes build number is the last number in the name)
      build_number=$(echo "$build_name_noapp" | grep -oE '[0-9]+$')
      new_json_path="${series_folder}/score${score}_build${build_number}.json"
      mv "$resultsFilePath" "$new_json_path"
      echo "Renamed JSON results to $new_json_path"
    else
      echo "Warning: Could not extract score from static files"
    fi
  else
    echo "Warning: Could not find HTML report at $reportPath"
  fi
  
done

echo "\nAll builds tested." 