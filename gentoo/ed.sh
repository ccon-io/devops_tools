#!/bin/bash

set -u -o pipefail

declare -i gitPush='0'
declare -i gitPull='0'
declare -i gitCommit='0'

declare -i doSudo='0'

declare -r GIT='/usr/bin/git'
declare -r SUM='/usr/bin/md5sum'
declare -r STAT='/usr/bin/stat'
declare -r GREP='/bin/egrep'
declare -r EDITOR='/usr/bin/vim'
declare -r SUDO='/usr/bin/sudo'

#Do not go quietly into that good night
die () {
  echo "${1}"
  exit "${2}"
}

#Need one arg to continue
if (( ${#@} < 1 ))
then
  echo "Specify a file to hack on"
  exit 1
else
  declare TARGET=${1}
fi

#wrapping git functions
runGit () {
  case $1 in
    push)
      ${GIT} push || die "Could not push to git" '1'
    ;;
    pull)
      ${GIT} push || die "Could not pull from git" '1'
    ;;
    add)
      ${GIT} add ${2} || die "Could not git add ${2}" '1'
    ;;
    commit)
      ${GIT} commit || die "Could not commit"
    ;;
    status)
      #Check status of current repo -- thanks internet guy!
      gitPush=0
      gitPull=0
      LOCAL=$(${GIT} rev-parse @)
      REMOTE=$(${GIT} rev-parse @{u})
      BASE=$(${GIT} merge-base @ @{u})
      if [ $LOCAL = $REMOTE ]; then
        retMsg="Up-to-date"
        return 0
      elif [ $LOCAL = $BASE ]; then
        retMsg="Pull Required"
        gitPull=1
        return 0
      elif [ $REMOTE = $BASE ]; then
        retMsg="Push Required"
        gitPush=1
        return 0
      else
        retMsg="Divergent"
        return 1
      fi
    ;; 
  esac
}

runGit status
retVal=$?

if (( retVal > 0 ))
then
  die "${retMsg}" "${retVal}"
fi

[[ -f ${TARGET} ]] || die "No such file" '1'
[[ -w ${TARGET} ]] || doSudo='1'

(( gitPush == 0 )) && runGit 'push'
(( gitPull == 0 )) && runGit 'pull'

targetMtimePre=$(${STAT} ${TARGET} | ${GREP} ^Modify | ${SUM})
if (( doSudo == 1 ))
then
  ${SUDO} ${EDITOR} ${TARGET}
else
  ${EDITOR} ${TARGET}
fi
targetMtimePost=$(${STAT} ${TARGET} | ${GREP} ^Modify| ${SUM})

[[ ! ${targetMtimePre} == ${targetMtimePost} ]] && gitCommit=1

if (( gitCommit == 1 ))
then
  if [[ -f ./README.md ]]
  then
    MD5SUM=$(${SUM} ${TARGET}|awk '{ print $1 }')
    (( $? == 0 )) || die "Could not ${SUM} ${TARGET}" 1

    #Check for existing md5sum
    egrep "^${TARGET}.*MD5" README.md &> /dev/null
    if (( $? == 0 ))
    then
      sed -i "s/\(^$(basename ${TARGET}).*MD5:\).*$/\1 ${MD5SUM}/" README.md || die "Could not replace MD5" '1'
    else
      sed -i "s/\(^$(basename ${TARGET}).*$\)/\1 \| MD5: ${MD5SUM}/" README.md || die "Could not append MD5: ${MD5SUM}" '1'
    fi
    runGit 'add' 'README.md'
  fi

  runGit 'add' "${TARGET}"
  runGit 'commit'
fi

runGit status
if (( retVal > 0 ))
then
  die "${retMsg}" "${retVal}"
fi

(( gitPush == 1 )) && runGit push && die "Changes pushed" "0"
(( gitPull == 1 )) && runGit pull && die "Changes pulled" "0"
die "Nothing eh?" "0"
