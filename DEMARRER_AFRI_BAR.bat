@echo off
REM ====================================================================
REM   AFRI-BAR Manager — Lanceur Windows (serveur local)
REM   Démarre un serveur HTTP local pour faire fonctionner localStorage
REM   Compatible Chrome, Firefox, Edge sur Windows / Tablette Android
REM ====================================================================
chcp 65001 >nul
title AFRI-BAR Manager — Serveur local

echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║       AFRI-BAR Manager — Demarrage du serveur local      ║
echo  ║       Depot de boissons - Cote d'Ivoire                  ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.

REM Verification Python
where python >nul 2>nul
if %errorlevel% neq 0 (
    where py >nul 2>nul
    if %errorlevel% neq 0 (
        echo  [!] Python n'est pas installe.
        echo.
        echo  Vous pouvez ouvrir directement le fichier AfriBar_Manager.html
        echo  avec Firefox (Firefox supporte localStorage en mode file://).
        echo.
        echo  Pour utiliser Chrome / tablette Android, installez Python depuis :
        echo  https://www.python.org/downloads/
        echo.
        pause
        exit /b 1
    )
    set PYCMD=py
) else (
    set PYCMD=python
)

REM Recherche du fichier HTML
if not exist "AfriBar_Manager.html" (
    echo  [!] Fichier AfriBar_Manager.html introuvable dans ce dossier.
    pause
    exit /b 1
)

echo  ✓ Serveur demarre sur http://localhost:8080
echo  ✓ Ouverture du navigateur dans 2 secondes...
echo.
echo  [INFO] NE FERMEZ PAS cette fenetre pendant l'utilisation.
echo  [INFO] Pour arreter le serveur : appuyez sur Ctrl+C
echo.

timeout /t 2 /nobreak >nul
start http://localhost:8080/AfriBar_Manager.html

%PYCMD% -m http.server 8080
