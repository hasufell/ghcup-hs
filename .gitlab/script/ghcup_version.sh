#!/bin/sh

set -eux

. "$( cd "$(dirname "$0")" ; pwd -P )/../ghcup_env"

mkdir -p "$CI_PROJECT_DIR"/.local/bin

CI_PROJECT_DIR=$(pwd)

ecabal() {
	cabal "$@"
}

eghcup() {
	if [ "${OS}" = "WINDOWS" ] ; then
		ghcup -v -c -s file:/$CI_PROJECT_DIR/ghcup-${JSON_VERSION}.yaml "$@"
	else
		ghcup -v -c -s file://$CI_PROJECT_DIR/ghcup-${JSON_VERSION}.yaml "$@"
	fi
}

git describe --always

### build

ecabal update

(
	cd /tmp
	ecabal install -w ghc-${GHC_VERSION} --installdir="$CI_PROJECT_DIR"/.local/bin hspec-discover
)

if [ "${OS}" = "DARWIN" ] ; then
	ecabal build -w ghc-${GHC_VERSION} -ftui
	ecabal test -w ghc-${GHC_VERSION} -ftui ghcup-test
	ecabal haddock -w ghc-${GHC_VERSION} -ftui
elif [ "${OS}" = "LINUX" ] ; then
	if [ "${ARCH}" = "32" ] ; then
		ecabal build -w ghc-${GHC_VERSION} -finternal-downloader -ftui -ftar
		ecabal test -w ghc-${GHC_VERSION} -finternal-downloader -ftui -ftar ghcup-test
		ecabal haddock -w ghc-${GHC_VERSION} -finternal-downloader -ftui -ftar
	else
		ecabal build -w ghc-${GHC_VERSION} -finternal-downloader -ftui
		ecabal test -w ghc-${GHC_VERSION} -finternal-downloader -ftui ghcup-test
		ecabal haddock -w ghc-${GHC_VERSION} -finternal-downloader -ftui
	fi
elif [ "${OS}" = "FREEBSD" ] ; then
	ecabal build -w ghc-${GHC_VERSION} -finternal-downloader -ftui --constraint="zip +disable-zstd"
	ecabal test -w ghc-${GHC_VERSION} -finternal-downloader -ftui --constraint="zip +disable-zstd" ghcup-test
	ecabal haddock -w ghc-${GHC_VERSION} -finternal-downloader -ftui --constraint="zip +disable-zstd"
elif [ "${OS}" = "WINDOWS" ] ; then
	ecabal build -w ghc-${GHC_VERSION}
	ecabal test -w ghc-${GHC_VERSION} ghcup-test
	ecabal haddock -w ghc-${GHC_VERSION}
else
	ecabal build -w ghc-${GHC_VERSION} -finternal-downloader -ftui
	ecabal test -w ghc-${GHC_VERSION} -finternal-downloader -ftui ghcup-test
	ecabal haddock -w ghc-${GHC_VERSION} -finternal-downloader -ftui
fi


if [ "${OS}" = "WINDOWS" ] ; then
	ext=".exe"
else
	ext=''
fi
	cp "$(ecabal new-exec -w ghc-${GHC_VERSION} --verbose=0 --offline sh -- -c 'command -v ghcup')" "$CI_PROJECT_DIR"/.local/bin/ghcup${ext}
	cp "$(ecabal new-exec -w ghc-${GHC_VERSION} --verbose=0 --offline sh -- -c 'command -v ghcup-gen')" "$CI_PROJECT_DIR"/.local/bin/ghcup-gen${ext}

### cleanup

if [ "${OS}" = "WINDOWS" ] ; then
	rm -rf "${GHCUP_INSTALL_BASE_PREFIX}"/ghcup
else
	rm -rf "${GHCUP_INSTALL_BASE_PREFIX}"/.ghcup
fi

### manual cli based testing


ghcup-gen check -f ghcup-${JSON_VERSION}.yaml

eghcup --numeric-version

eghcup install ${GHC_VERSION}
[ `$(eghcup whereis ghc ${GHC_VERSION}) --numeric-version` = "${GHC_VERSION}" ]
eghcup set ${GHC_VERSION}
eghcup install-cabal ${CABAL_VERSION}
[ `$(eghcup whereis cabal ${CABAL_VERSION}) --numeric-version` = "${CABAL_VERSION}" ]

cabal --version

eghcup debug-info

eghcup list
eghcup list -t ghc
eghcup list -t cabal

ghc_ver=$(ghc --numeric-version)
ghc --version
ghc-${ghc_ver} --version
if [ "${OS}" != "WINDOWS" ] ; then
		ghci --version
		ghci-${ghc_ver} --version
fi


if [ "${OS}" = "DARWIN" ] && [ "${ARCH}" = "ARM64" ] ; then
	echo
else
	# test installing new ghc doesn't mess with currently set GHC
	# https://gitlab.haskell.org/haskell/ghcup-hs/issues/7
	if [ "${OS}" = "LINUX" ] ; then
		eghcup --downloader=wget install 8.10.3
	else # test wget a bit
		eghcup install 8.10.3
	fi
	[ "$(ghc --numeric-version)" = "${ghc_ver}" ]
	eghcup set 8.10.3
	eghcup set 8.10.3
	[ "$(ghc --numeric-version)" = "8.10.3" ]
	eghcup set ${GHC_VERSION}
	[ "$(ghc --numeric-version)" = "${ghc_ver}" ]
	eghcup rm 8.10.3
	[ "$(ghc --numeric-version)" = "${ghc_ver}" ]

	if [ "${OS}" = "DARWIN" ] ; then
		eghcup install hls
		$(eghcup whereis hls) --version

		eghcup install stack
		$(eghcup whereis stack) --version
	elif [ "${OS}" = "LINUX" ] ; then
		if [ "${ARCH}" = "64" ] ; then
			eghcup install hls
			haskell-language-server-wrapper --version

			eghcup install stack
			stack --version
		fi
	fi
fi


eghcup rm $(ghc --numeric-version)

# https://gitlab.haskell.org/haskell/ghcup-hs/-/issues/116
if [ "${OS}" = "LINUX" ] ; then
	if [ "${ARCH}" = "64" ] ; then
		eghcup install cabal -u https://oleg.fi/cabal-install-3.4.0.0-rc4/cabal-install-3.4.0.0-x86_64-ubuntu-16.04.tar.xz 3.4.0.0-rc4
		eghcup rm cabal 3.4.0.0-rc4
	fi
fi

eghcup upgrade
eghcup upgrade -f


# nuke
eghcup nuke
if [ "${OS}" = "WINDOWS" ] ; then
	[ ! -e "${GHCUP_INSTALL_BASE_PREFIX}/ghcup" ]
else
	[ ! -e "${GHCUP_INSTALL_BASE_PREFIX}/.ghcup" ]
fi
