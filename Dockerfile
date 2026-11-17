FROM mcr.microsoft.com/dotnet/sdk:8.0-bookworm-slim AS build
WORKDIR /src
COPY src/QuanLyNghiPhep/QuanLyNghiPhep.csproj src/QuanLyNghiPhep/
RUN dotnet restore src/QuanLyNghiPhep/QuanLyNghiPhep.csproj
COPY src/QuanLyNghiPhep/ src/QuanLyNghiPhep/
RUN dotnet publish src/QuanLyNghiPhep/QuanLyNghiPhep.csproj -c Release --no-restore -o /publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0-bookworm-slim
WORKDIR /app
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0700 -o app -g app /app/AppData
COPY --from=build /publish/ ./
ENV ASPNETCORE_HTTP_PORTS=8989 \
    ASPNETCORE_ENVIRONMENT=Production \
    TZ=Asia/Ho_Chi_Minh
EXPOSE 8989
USER app
ENTRYPOINT ["dotnet", "QuanLyNghiPhep.dll"]
