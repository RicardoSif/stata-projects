********************************************************************************
* PROYECTO: Inclusión Financiera y Métodos de Pago (ENAHO 2015-2024)
* PROPÓSITO: Fusión con datos externos y Estimación de Impacto (Diff-in-Diff)
********************************************************************************

use "$output/payment_methods_final", clear

*FUSIÓN CON DATOS EXTERNOS (EXPOSURE & CASHLESS RATIOS)

*Nota: Se vincula la ENAHO con datos a nivel de ciudad (ubigeo)

rename period date
rename ubigeo city

*Merge con ratio de exposición fintech
merge m:1 city using "$output/ratio_new", keep(3) nogen 

*Estandarización de la variable de exposición (Z-score)
replace io_exposure = 0 if io_exposure == .
summarize io_exposure
gen io_exposure_sd = io_exposure / r(sd)

*Merge con niveles de digitalización previa
merge m:1 city using "$output/cashless_and_treatment", keep(3) nogen
summarize cel_per, detail
gen high_mobile = (cel_per > r(p25))

*CONSTRUCCIÓN DE CONTROLES SOCIOECONÓMICOS

rename city ubigeo
rename p207 gender
destring ubigeo, replace

*Definición de cohortes y variables demográficas
gen birth_year = year - p208a
gen young = (birth_year >= 1990) if birth_year < .
label var young "Nacido después de 1989"

*Condición laboral (PEA) y Educación
recode ocu500 (1/2 = 1 "PEA") (3/4 = 2 "PEI"), gen(eap)
recode p301a (1/5 = 1 "Sec. Incompleta") (6/11 = 2 "Sec. Completa o más") (12=.), gen(high_school)

*Informalidad e independencia (p507)
gen byte informal = (ocupinf == 1) if inlist(ocupinf, 1, 2)
gen byte indep = inlist(p507, 1, 2)
gen byte employer = (p507 == 1)


*EFECTOS FIJOS Y DINÁMICOS

*Definición de grupos de interacción (FE de alta dimensión)
egen urbano_time   = group(urbano date)
egen young_time    = group(young date)
gen region         = floor(ubigeo/10000)
egen region_time   = group(region date)

*Variables para el Event Study
keep if date > tq(2018q4)
drop if inlist(date, tq(2020q2), tq(2020q3)) // Limpieza de periodos atípicos COVID
sort date
egen time_period = group(date)

summarize time_period
forvalues j = 1/`r(max)' {
gen exposure_sd_t`j' = io_exposure_sd * (time_period == `j')
}
*Se omite el periodo 15 como base (referencia pre-boom)
cap drop exposure_sd_t15 


*ESTIMACIÓN REGHDFE Y GRÁFICO DE EVENT STUDY

*Estimamos el impacto sobre Acceso a Crédito

global fe_spec "ubigeo date urbano_time young_time region_time"

reghdfe acceso_credito exposure_sd_t* [aw = fac500a], abs($fe_spec) vce(cl ubigeo)

* Almacenamiento de coeficientes para el gráfico
gen B = .
gen L = .
gen U = .
gen periods = _n

forvalues h = 1/25 {
capture {
replace B = _b[exposure_sd_t`h'] if _n == `h'
replace L = _b[exposure_sd_t`h'] - 1.96 * _se[exposure_sd_t`h'] if _n == `h'
replace U = _b[exposure_sd_t`h'] + 1.96 * _se[exposure_sd_t`h'] if _n == `h'
}
}

*Visualización del impacto dinámico
twoway (rcap L U periods, lp(dash) lc(navy) lw(vthin)) ///
(scatter B periods, m(diamond) mfc(white) mc(navy) mlw(medthick)), ///
yline(0, lcolor(black)) xline(15, lcolor(gs10) lp(dash)) ///
xlabel(1 "2019q1" 7 "2021q1" 15 "2023q1" 23 "2025q1", grid) ///
ytitle("Coeficiente Diff-in-Diff") xtitle("Trimestre") ///
title("Impacto de Exposición Fintech en Acceso a Crédito") ///
graphregion(color(white)) legend(off)

graph export "$result/did_impact_credit.pdf", replace
