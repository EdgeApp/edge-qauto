#!/bin/zsh
setopt null_glob

# Source the qauto environment if the file exists
if [ -f ./qauto ]; then
  source ./qauto
fi

# Set iteration count
iterationCount=1

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
    --resultsTitle '$test_type_folder_capitalized $build_name_noapp' \
    --iterationCount '$iterationCount';"
  eval $cmd
  set +e
  # echo "Results saved to $resultsFilePath" # redundant

  # Generate HTML report and extract score
  flashlight report "$resultsFilePath"

  # Calculate score directly from JSON data using the full Flashlight formula
  if [[ -f "$resultsFilePath" ]]; then
    # Use jq to perform the complete score calculation, matching the flashlight source.
    score=$(jq -r '
      def clamp(x; min; max): [min, x, max] | sort | .[1];
      90 as $cpuThreshold |

      # --- Data Extraction and Filtering ---
      # 1. Create a flat list of all measures from all iterations.
      [ .iterations[].measures[] ] as $all_measures |

      # 2. Create a list for CPU Score calculation (using total core usage)
      [
        $all_measures[] | {
          cpu: (.cpu.perCore | values | add),
          time: .time
        } | select(.cpu != null and .time != null)
      ] as $cpu_score_measures |
      
      # 3. Create a list for Penalty calculation (using thread-specific usage)
      [
        $all_measures[] | {
          cpu: (.cpu.perName["UI Thread"]? + .cpu.perName["Jit thread pool"]?),
          time: .time
        } | select(.cpu != null and .time != null)
      ] as $penalty_measures |

      # 4. Create a list of all valid FPS measures
      [ $all_measures[].fps | select(. != null) ] as $fps_measures |

      # Proceed only if we have valid data to analyze
      if ($cpu_score_measures | length) > 0 and ($penalty_measures | length) > 0 and ($fps_measures | length) > 0 then
        # --- Penalty Calculation (Thread-specific) ---
        ($penalty_measures | map(.time) | add) as $totalPenaltyTime |
        ($penalty_measures | map(select(.cpu > $cpuThreshold).time) | add) as $highCpuTime |
        (if $totalPenaltyTime > 0 then $highCpuTime / $totalPenaltyTime else 0 end) as $penalty |

        # --- Sub-Score Calculation (Using different CPU metrics) ---
        ( ($fps_measures | add) / ($fps_measures | length) ) as $avgFps |
        # avgCpu for score is the sum of all cores
        ( ($cpu_score_measures | map(.cpu) | add) / ($cpu_score_measures | length) ) as $avgCpuForScore |
        clamp(-0.3166666667 * $avgCpuForScore + 116; 0; 100) as $cpuScore |
        (100 * $avgFps / 60) as $fpsScore |

        # --- Final Score Calculation ---
        ( ( ($cpuScore + $fpsScore) / 2 ) * (1 - $penalty) ) | round
      else
        empty
      end
    ' "$resultsFilePath")
    
    if [[ -n "$score" && "$score" != "null" ]]; then
      echo "Calculated score: $score"
      # Extract build number from build_name_noapp (assumes build number is the last number in the name)
      build_number=$(echo "$build_name_noapp" | grep -oE '[0-9]+$')
      new_json_path="${series_folder}/score${score}_build${build_number}.json"
      mv "$resultsFilePath" "$new_json_path"
      echo "Renamed JSON results to $new_json_path"
    else
      echo "Warning: Could not calculate score from JSON data"
    fi
  else
    echo "Warning: Could not find JSON results file at $resultsFilePath"
  fi
  
done

echo "\nAll builds tested." 