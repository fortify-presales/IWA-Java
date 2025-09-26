@echo on

docker pull fortifydocker/fortify-connect:25.2.alpine.3.18
docker run --name fdc_client -d ^
  -e "FDC_ADDRESS=emea.fodconnect.com:443" ^
  -e "FDC_UNAME=1172_klee2@opentext.com_klee2-local" ^
  -e "FDC_UPSWD=Password123!" ^
  -e "FDC_PROXY=3128" ^
  --privileged fortifydocker/fortify-connect:25.2.alpine.3.18