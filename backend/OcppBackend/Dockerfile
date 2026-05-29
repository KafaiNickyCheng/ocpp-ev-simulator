# backend/OcppBackend/Dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY backend/OcppBackend/*.csproj backend/OcppBackend/
RUN dotnet restore backend/OcppBackend/

COPY backend/OcppBackend/. backend/OcppBackend/
RUN dotnet publish backend/OcppBackend/ -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:${PORT:-5000}

ENTRYPOINT ["dotnet", "OcppBackend.dll"]