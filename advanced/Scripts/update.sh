#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Check Pi-hole core and FTL versions and determine what
# upgrade (if any) is required. Automatically updates and reinstalls
# application if update is detected.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
readonly PI_HOLE_GIT_URL="https://github.com/pi-hole/pi-hole.git"
readonly PI_HOLE_FILES_DIR="/etc/.pihole"

# shellcheck disable=SC2034
PH_TEST=true

# when --check-only is passed to this script, it will not perform the actual update
CHECK_ONLY=false

# shellcheck disable=SC1090
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"
# shellcheck disable=SC1091
source "/opt/pihole/COL_TABLE"

# is_repo() sourced from basic-install.sh
# make_repo() sourced from basic-install.sh
# update_repo() source from basic-install.sh
# getGitFiles() sourced from basic-install.sh
# get_binary_name() sourced from basic-install.sh
# FTLcheckUpdate() sourced from basic-install.sh
# APIcheckUpdate() sourced from basic-install.sh
# simple_distro_check sourced from basic-install.sh

GitCheckUpdateAvail() {
    local directory
    directory="${1}"
    curdir=$PWD
    cd "${directory}" || return

    # Fetch latest changes in this repo
    git fetch --quiet origin

    # @ alone is a shortcut for HEAD. Older versions of git
    # need @{0}
    LOCAL="$(git rev-parse "@{0}")"

    # The suffix @{upstream} to a branchname
    # (short form <branchname>@{u}) refers
    # to the branch that the branch specified
    # by branchname is set to build on top of#
    # (configured with branch.<name>.remote and
    # branch.<name>.merge). A missing branchname
    # defaults to the current one.
    REMOTE="$(git rev-parse "@{upstream}")"

    if [[ "${#LOCAL}" == 0 ]]; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Local revision could not be obtained, please contact Pi-hole Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit
    fi
    if [[ "${#REMOTE}" == 0 ]]; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Remote revision could not be obtained, please contact Pi-hole Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit
    fi

    # Change back to original directory
    cd "${curdir}" || exit

    if [[ "${LOCAL}" != "${REMOTE}" ]]; then
        # Local branch is behind remote branch -> Update
        return 0
    else
        # Local branch is up-to-date or in a situation
        # where this updater cannot be used (like on a
        # branch that exists only locally)
        return 1
    fi
}

# Print a warning if the user is on a non-standard branch
checkCustomBranch() {
    local program
    local branch
    program="$1"
    branch="$2"

    if [[ ! "${branch}" == "master" && ! "${branch}" == "development" ]]; then
        # Notify user that they are on a custom branch which might mean they they are lost
        # behind if a branch was merged to development and got abandoned
        printf "  %b %bWarning:%b You are using %s from a custom branch (%s) and might be missing future releases.\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}" "${program}" "${branch}"
    fi
}

main() {
    local basicError="\\n  ${COL_LIGHT_RED}Unable to complete update, please contact Pi-hole Support${COL_NC}"
    local core_update
    local FTL_update
    local API_update

    core_update=false
    FTL_update=false
    API_update=false

    # shellcheck disable=1090,2154
    source "${setupVars}"

    # Get the distro information so get_binary_name can correctly determine the
    # file name to use
    simple_distro_check

    # This is unlikely
    if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Core Pi-hole repo is missing from system!"
        echo -e "  Please re-run install script from https://pi-hole.net${COL_NC}"
        exit 1;
    fi

    echo -e "  ${INFO} Checking for updates..."

    if GitCheckUpdateAvail "${PI_HOLE_FILES_DIR}" ; then
        core_update=true
        echo -e "  ${INFO} Pi-hole Core:\\t${COL_YELLOW}update available${COL_NC}"
    else
        core_update=false
        echo -e "  ${INFO} Pi-hole Core:\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
    fi

    if FTLcheckUpdate > /dev/null; then
        FTL_update=true
        echo -e "  ${INFO} FTL:\\t\\t${COL_YELLOW}update available${COL_NC}"
    else
        case $? in
            1)
                echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
                ;;
            2)
                echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_RED}Branch is not available.${COL_NC}\\n\\t\\t\\tUse ${COL_LIGHT_GREEN}pihole checkout ftl [branchname]${COL_NC} to switch to a valid branch."
                ;;
            *)
                echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_RED}Something has gone wrong, contact support${COL_NC}"
        esac
        FTL_update=false
    fi

    if APIcheckUpdate > /dev/null; then
        API_update=true
        echo -e "  ${INFO} API:\\t\\t${COL_YELLOW}update available${COL_NC}"
    else
        case $? in
            1)
                echo -e "  ${INFO} API:\\t\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
                ;;
            2)
                echo -e "  ${INFO} API:\\t\\t${COL_LIGHT_RED}Branch is not available.${COL_NC}\\n\\t\\t\\tUse ${COL_LIGHT_GREEN}pihole checkout api [branchname]${COL_NC} to switch to a valid branch."
                ;;
            *)
                echo -e "  ${INFO} API:\\t\\t${COL_LIGHT_RED}Something has gone wrong, contact support${COL_NC}"
        esac
        API_update=false
    fi

    # Determine FTL branch
    local ftlBranch
    if [[ -f "/etc/pihole/ftlbranch" ]]; then
        ftlBranch=$(</etc/pihole/ftlbranch)
    else
        ftlBranch="master"
    fi

    # Determine API branch
    local apiBranch
    if [[ -f "/etc/pihole/apibranch" ]];then
        apiBranch=$(</etc/pihole/apibranch)
    else
        apiBranch="master"
    fi

    checkCustomBranch FTL "${ftlBranch}"
    checkCustomBranch API "${apiBranch}"

    if [[ "${core_update}" == false && "${FTL_update}" == false && "${API_update}" == false ]]; then
        echo ""
        echo -e "  ${TICK} Everything is up to date!"
        exit 0
    fi

    if [[ "${CHECK_ONLY}" == true ]]; then
        echo ""
        exit 0
    fi

    if [[ "${core_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} Pi-hole core files out of date, updating local repo."
        getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
        echo -e "  ${INFO} If you had made any changes in '/etc/.pihole/', they have been stashed using 'git stash'"
    fi

    if [[ "${FTL_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} FTL out of date, it will be updated by the installer."
    fi

    if [[ "${API_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} API out of date, it will be updated by the installer."
    fi

    if [[ "${core_update}" == true || "${FTL_update}" == true || "${API_update}" == true ]]; then
        ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --reconfigure --unattended || \
        echo -e "${basicError}" && exit 1
    fi
    echo ""
    exit 0
}

if [[ "$1" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

main
