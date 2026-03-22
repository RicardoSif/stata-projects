********************************************************************************
* PROYECTO: Inclusión financiera y métodos de pago (ENAHO 2015-2024)
* PROPÓSITO: Automatización de descarga, armonización de microdatos y análisis.
* Año: 2025
********************************************************************************

clear all
set more off, perm
#delimit cr

*CONFIGURACIÓN DE RUTAS DINÁMICAS

*Esta sección permite que el código sea reproducible en distintos entornos de trabajo mediante la identificación del usuario del sistema.

if "`c(username)'"=="USUARIO"{
	global dropbox "/Users/USUARIO/Dropbox"
	global projectfolder "$dropbox/Proyecto_fintech"
}

* Definición de subcarpetas funcionales
global source        "$projectfolder/data/source"
global output        "$projectfolder/data/output"
global result        "$projectfolder/results"
global code          "$projectfolder/code"
global survey_docs   "$projectfolder/survey"
global dictionary    "$projectfolder/dictionary"

*DESCARGA AUTOMATIZADA DESDE SERVIDOR INEI

global inei "https://proyectos.inei.gob.pe/iinei/srienaho/descarga/STATA"

*Diccionario de códigos de descarga (Módulo 05 - Empleo y Previsión Social)
*2015: 498 | 2016: 546 | 2017: 603 | 2018: 634 | 2019: 687 
*2020: 737 | 2021: 759 | 2022: 784 | 2023: 906 | 2024: 966

local codes "498 546 603 634 687 737 759 784 906 966"
local years "2015 2016 2017 2018 2019 2020 2021 2022 2023 2024"

*Loop para descarga y extracción
forvalues i = 1/10 {
local c : word `i' of `codes'
local y : word `i' of `years'
    
display "Procesando ENAHO `y' (Código `c')..."
    
copy "$inei/`c'-Modulo05.zip" "$source/`c'-Modulo05.zip", replace
    
shell tar -xf "$source/`c'-Modulo05.zip" -C "$source/yearly"
erase "$source/`c'-Modulo05.zip"
    
*Copia del archivo .dta y limpieza de temporales
copy "$source/yearly/`c'-Modulo05/enaho01a-`y'-500.dta" "$source/enaho01a-`y'-500.dta", replace
erase "$source/yearly/`c'-Modulo05/enaho01a-`y'-500.dta"
    
*Organización de documentación técnica (Manuales y Diccionarios)
cap !move "$source/yearly/`c'-Modulo05/*.pdf" "$survey_docs/"
}

*ARMONIZACIÓN Y CONSTRUCCIÓN DE PANEL (APPEND)
*Se unifican las bases anuales en una serie de tiempo larga, manejando inconsistencias en nombres de variables y formatos.

forvalues i = 2015/2024 {
use "$source/enaho01a-`i'-500.dta", clear
display "Añadiendo año: `i'"
    
gen year = `i'
    
*Estandarización de variables de tiempo (limpieza de caracteres especiales)
cap drop a*o 
    
* Consolidación progresiva
if `i' != 2015 {
append using "$output/labor_2015_2024_CS", force
}
    
save "$output/labor_2015_2024_CS", replace
}


*4.LIMPIEZA FINAL 
*Eliminar carpetas temporales y archivos intermedios para optimizar espacio

!for /d %x in ("$source/yearly/*") do rd /s /q "%x"

forvalues i = 2015/2024 {
    cap erase "$source/enaho01a-`i'-500.dta"
}
