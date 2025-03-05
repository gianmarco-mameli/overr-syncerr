FROM mcr.microsoft.com/powershell:7.4-debian-12

WORKDIR /app

COPY . .

ENTRYPOINT ["pwsh", "/app/overr-syncerr-main.ps1"]
