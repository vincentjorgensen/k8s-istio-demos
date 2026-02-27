make -f ./Makefile.selfsigned.mk root-ca
make -f ./Makefile.selfsigned.mk cluster1-cacerts
make -f ./Makefile.selfsigned.mk cluster2-cacerts
make -f ./Makefile.selfsigned.mk cluster3-cacerts
make -f ./Makefile.selfsigned.mk cluster4-cacerts
