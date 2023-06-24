.PHONY: fmt

fmt:
	shfmt -i 2 -s -w picoregress.sh

checkfmt:
	shfmt -i 2 -s -d picoregress.sh

check:
	shellcheck --severity=info picoregress.sh

resetoutput:
	rm -rf testenv/*/output/*
