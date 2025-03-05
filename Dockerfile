FROM mcr.microsoft.com/powershell

WORKDIR /app

COPY . .

ENTRYPOINT ["pwsh", "/app/overr-syncerr-main.ps1"]
