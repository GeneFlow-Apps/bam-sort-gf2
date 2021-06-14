#!/bin/bash -l

# BAM sort with SAMTools wrapper script


###############################################################################
#### Helper Functions ####
###############################################################################

## ****************************************************************************
## Usage description should match command line arguments defined below
usage () {
    echo "Usage: $(basename "$0")"
    echo "  --input => Input BAM File"
    echo "  --sort_order => Sort Order"
    echo "  --output => Output BAM File"
    echo "  --exec_method => Execution method (docker, auto)"
    echo "  --exec_init => Execution initialization command(s)"
    echo "  --help => Display this help message"
}
## ****************************************************************************

# report error code for command
safeRunCommand() {
    cmd="$@"
    eval "$cmd; "'PIPESTAT=("${PIPESTATUS[@]}")'
    for i in ${!PIPESTAT[@]}; do
        if [ ${PIPESTAT[$i]} -ne 0 ]; then
            echo "Error when executing command #${i}: '${cmd}'"
            exit ${PIPESTAT[$i]}
        fi
    done
}

# print message and exit
fail() {
    msg="$@"
    echo "${msg}"
    usage
    exit 1
}

# always report exit code
reportExit() {
    rv=$?
    echo "Exit code: ${rv}"
    exit $rv
}

trap "reportExit" EXIT

# check if string contains another string
contains() {
    string="$1"
    substring="$2"

    if test "${string#*$substring}" != "$string"; then
        return 0    # $substring is not in $string
    else
        return 1    # $substring is in $string
    fi
}



###############################################################################
## SCRIPT_DIR: directory of current script, depends on execution
## environment, which may be detectable using environment variables
###############################################################################
if [ -z "${AGAVE_JOB_ID}" ]; then
    # not an agave job
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
else
    echo "Agave job detected"
    SCRIPT_DIR=$(pwd)
fi
## ****************************************************************************



###############################################################################
#### Parse Command-Line Arguments ####
###############################################################################

getopt --test > /dev/null
if [ $? -ne 4 ]; then
    echo "`getopt --test` failed in this environment."
    exit 1
fi

## ****************************************************************************
## Command line options should match usage description
OPTIONS=
LONGOPTIONS=help,exec_method:,exec_init:,input:,sort_order:,output:,
## ****************************************************************************

# -temporarily store output to be able to check for errors
# -e.g. use "--options" parameter by name to activate quoting/enhanced mode
# -pass arguments only via   -- "$@"   to separate them correctly
PARSED=$(\
    getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@"\
)
if [ $? -ne 0 ]; then
    # e.g. $? == 1
    #  then getopt has complained about wrong arguments to stdout
    usage
    exit 2
fi

# read getopt's output this way to handle the quoting right:
eval set -- "$PARSED"

## ****************************************************************************
## Set any defaults for command line options
SORT_ORDER="coordinate"
EXEC_METHOD="auto"
EXEC_INIT=":"
## ****************************************************************************

## ****************************************************************************
## Handle each command line option. Lower-case variables, e.g., ${file}, only
## exist if they are set as environment variables before script execution.
## Environment variables are used by Agave. If the environment variable is not
## set, the Upper-case variable, e.g., ${FILE}, is assigned from the command
## line parameter.
while true; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --input)
            if [ -z "${input}" ]; then
                INPUT=$2
            else
                INPUT="${input}"
            fi
            shift 2
            ;;
        --sort_order)
            if [ -z "${sort_order}" ]; then
                SORT_ORDER=$2
            else
                SORT_ORDER="${sort_order}"
            fi
            shift 2
            ;;
        --output)
            if [ -z "${output}" ]; then
                OUTPUT=$2
            else
                OUTPUT="${output}"
            fi
            shift 2
            ;;
        --exec_method)
            if [ -z "${exec_method}" ]; then
                EXEC_METHOD=$2
            else
                EXEC_METHOD="${exec_method}"
            fi
            shift 2
            ;;
        --exec_init)
            if [ -z "${exec_init}" ]; then
                EXEC_INIT=$2
            else
                EXEC_INIT="${exec_init}"
            fi
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Invalid option"
            usage
            exit 3
            ;;
    esac
done
## ****************************************************************************

## ****************************************************************************
## Log any variables passed as inputs
echo "Input: ${INPUT}"
echo "Sort_order: ${SORT_ORDER}"
echo "Output: ${OUTPUT}"
echo "Execution Method: ${EXEC_METHOD}"
echo "Execution Initialization: ${EXEC_INIT}"
## ****************************************************************************



###############################################################################
#### Validate and Set Variables ####
###############################################################################

## ****************************************************************************
## Add app-specific logic for handling and parsing inputs and parameters

# INPUT input

if [ -z "${INPUT}" ]; then
    echo "Input BAM File required"
    echo
    usage
    exit 1
fi
# make sure INPUT is staged
count=0
while [ ! -f "${INPUT}" ]
do
    echo "${INPUT} not staged, waiting..."
    sleep 1
    count=$((count+1))
    if [ $count == 10 ]; then break; fi
done
if [ ! -f "${INPUT}" ]; then
    echo "Input BAM File not found: ${INPUT}"
    exit 1
fi
INPUT_FULL=$(readlink -f "${INPUT}")
INPUT_DIR=$(dirname "${INPUT_FULL}")
INPUT_BASE=$(basename "${INPUT_FULL}")



# SORT_ORDER parameter
if [ -n "${SORT_ORDER}" ]; then
    :
else
    :
fi


# OUTPUT parameter
if [ -n "${OUTPUT}" ]; then
    :
    OUTPUT_FULL=$(readlink -f "${OUTPUT}")
    OUTPUT_DIR=$(dirname "${OUTPUT_FULL}")
    OUTPUT_BASE=$(basename "${OUTPUT_FULL}")
    LOG_FULL="${OUTPUT_DIR}/_log"
    TMP_FULL="${OUTPUT_DIR}/_tmp"
else
    :
    echo "Output BAM File required"
    echo
    usage
    exit 1
fi

## ****************************************************************************

## EXEC_METHOD: execution method
## Suggested possible options:
##   auto: automatically determine execution method
##   singularity: singularity image packaged with the app
##   docker: docker containers from docker-hub
##   environment: binaries available in environment path

## ****************************************************************************
## List supported execution methods for this app (space delimited)
exec_methods="docker auto"
## ****************************************************************************

## ****************************************************************************
# make sure the specified execution method is included in list
if ! contains " ${exec_methods} " " ${EXEC_METHOD} "; then
    echo "Invalid execution method: ${EXEC_METHOD}"
    echo
    usage
    exit 1
fi
## ****************************************************************************



###############################################################################
#### App Execution Initialization ####
###############################################################################

## ****************************************************************************
## Execute any "init" commands passed to the GeneFlow CLI
CMD="${EXEC_INIT}"
echo "CMD=${CMD}"
safeRunCommand "${CMD}"
## ****************************************************************************



###############################################################################
#### Auto-Detect Execution Method ####
###############################################################################

# assign to new variable in order to auto-detect after Agave
# substitution of EXEC_METHOD
AUTO_EXEC=${EXEC_METHOD}
## ****************************************************************************
## Add app-specific paths to detect the execution method.
if [ "${EXEC_METHOD}" = "auto" ]; then
    # detect execution method
    if command -v docker >/dev/null 2>&1; then
        AUTO_EXEC=docker
    else
        echo "Valid execution method not detected"
        echo
        usage
        exit 1
    fi
    echo "Detected Execution Method: ${AUTO_EXEC}"
fi
## ****************************************************************************



###############################################################################
#### App Execution Preparation, Common to all Exec Methods ####
###############################################################################

## ****************************************************************************
## Add logic to prepare environment for execution
MNT=""; ARG=""; CMD0="mkdir -p ${LOG_FULL} ${ARG}"; CMD="${CMD0}"; echo "CMD=${CMD}"; safeRunCommand "${CMD}"; 
## ****************************************************************************



###############################################################################
#### App Execution, Specific to each Exec Method ####
###############################################################################

## ****************************************************************************
## Add logic to execute app
## There should be one case statement for each item in $exec_methods
case "${AUTO_EXEC}" in
    docker)
        MNT=""; ARG=""; fnrun0() { echo "samtools sort" | sed 's/>/\\>/g' | sed 's/</\\</g' | sed 's/|/\\|/g'; }; RUN_FULL='samtools sort'; eval "RUN_LIST=($(fnrun0))"; RUN=${RUN_LIST[0]}; for (( ri=1; ri<${#RUN_LIST[@]}; ri++ )); do if [ "${RUN_LIST[$ri]:0:1}" = "^" ]; then RARG="${RUN_LIST[$ri]#?}"; RARG_FULL=$(readlink -f "${RARG}"); RARG_DIR=$(dirname "${RARG}"); RARG_BASE=$(basename "${RARG}"); MNT="${MNT} -v "; MNT="${MNT}\"${RARG_DIR}:/data${ri}_r\""; ARG="${ARG} \"/data${ri}_r/${RARG_BASE}\""; else ARG="${ARG} ${RUN_LIST[$ri]}"; fi; done; MNT="${MNT} -v "; MNT="${MNT}\"${INPUT_DIR}:/data1\""; ARG="${ARG} \"/data1/${INPUT_BASE}\""; if [ "${SORT_ORDER}" = "queryname" ]; then ARG="${ARG} -n"; fi; CMD0="docker run --rm ${MNT} quay.io/biocontainers/samtools:1.10--h2e538c0_3 ${RUN} ${ARG}"; CMD0="${CMD0} >\"${OUTPUT_FULL}\""; CMD0="${CMD0} 2>\"${LOG_FULL}/${OUTPUT_BASE}-samtools-sort.stderr\""; CMD="${CMD0}"; echo "CMD=${CMD}"; safeRunCommand "${CMD}"; 
        ;;
esac
## ****************************************************************************



###############################################################################
#### Cleanup, Common to All Exec Methods ####
###############################################################################

## ****************************************************************************
## Add logic to cleanup execution artifacts, if necessary
## ****************************************************************************

