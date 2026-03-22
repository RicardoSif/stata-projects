********************************************************************************
* PROYECTO: Inclusión Financiera y Métodos de Pago (ENAHO 2015-2024)
* PROPÓSITO: Limpieza de datos, armonización de indicadores y análisis descriptivo.
********************************************************************************

use "$output/labor_2015_2024_CS", clear


* Filtro de residencia: Solo miembros del hogar presentes
gen filter = ((p204 == 1 & p205 == 2) | (p204 == 2 & p206 == 1))
label var filter "Filtro: Residentes habituales del hogar"

destring mes year, replace
gen quarter = .
replace quarter = 1 if inrange(mes, 1, 3)
replace quarter = 2 if inrange(mes, 4, 6)
replace quarter = 3 if inrange(mes, 7, 9)
replace quarter = 4 if inrange(mes, 10, 12)

gen period = yq(year, quarter)
format period %tq
label var period "Periodo trimestral"

*Ajuste de factor de expansión trimestral
gen fact_quarter = fac500a * 4
label var fact_quarter "Factor de expansión trimestral"


* ARMONIZACIÓN: MÉTODOS DE PAGO DIGITALES (2015-2024)

*Nota: Se maneja el cambio metodológico de 2024 donde se incluyen billeteras digitales y otros canales.

cap drop internet_cel
forvalues h = 1/12 {
quietly {
gen byte inet_`h' = .
        
* 2015-2023: Identificación de Banca por Internet (_4)
capture confirm variable p558h`h'_4
if !_rc {
replace inet_`h' = 1 if p558h`h'_4 == 4
replace inet_`h' = 0 if missing(inet_`h') & p558h`h'_4 != . & p558h`h'_4 != 4
}

* 2024 en adelante: Billetera Digital (_7) y Otros Canales (_8)
capture confirm variable p558h`h'_7
if !_rc {
replace inet_`h' = 1 if p558h`h'_7 == 7
replace inet_`h' = 0 if missing(inet_`h') & p558h`h'_7 != . & p558h`h'_7 != 7
       }
        
capture confirm variable p558h`h'_8
if !_rc {
replace inet_`h' = 1 if p558h`h'_8 == 8
replace inet_`h' = 0 if missing(inet_`h') & p558h`h'_8 != . & p558h`h'_8 != 8
}
}
}

egen internet_cel = rowmax(inet_1-inet_12)
egen __miss_all   = rowmiss(inet_1-inet_12)
replace internet_cel = . if __miss_all == 12
drop inet_* __miss_all
label var internet_cel "Pago mediante internet/celular"

*CONSTRUCCIÓN DE INDICADORES FINANCIEROS Y SOCIOECONÓMICOS

*Creación de dummies de métodos de pago
foreach v in 1 2 3 5 6 {
local name = cond(`v'==1, "cash", cond(`v'==2, "debit", cond(`v'==3, "credit", cond(`v'==5, "other", "not_buy"))))
egen temp_`v' = rowtotal(p558h*_`v'), missing
replace temp_`v' = temp_`v'/`v'
}

recode temp_1 (0=0) (1/12=1), gen(cash)
recode temp_2 (0=0) (1/12=1), gen(debit_card)
recode temp_3 (0=0) (1/12=1), gen(credit_card)
recode temp_5 (0=0) (1/12=1), gen(other_method)
recode temp_6 (0=0) (1/11=1) (12=2), gen(not_buy)
drop temp_*

*inclusión financiera: cuentas y crédito
gen cuenta_bancaria = inlist(1, p558e1_1, p558e1_2, p558e1_3, p558e1_7)
replace cuenta_bancaria = 0 if p558e1_6 == 6

gen acceso_credito = .
replace acceso_credito = (p558e3_1 == 1) if period < tq(2024q1)
replace acceso_credito = (p558e1_9 == 9) if period >= tq(2024q1)

gen urbano = inrange(estrato, 1, 6)
label values urbano lbl_urb


*ANÁLISIS AGREGADO Y EXPORTACIÓN DE RESULTADOS

preserve
* Limpieza para cálculo de porcentajes poblacionales
drop if internet_cel == .
keep if filter == 1 & not_buy != 2

*Cálculo manual de tasas para gráficos (manejo de factores de expansión)
egen population = sum(fac500a), by(year)
gen internet_cel_per = (internet_cel * fac500a / population) * 100
egen internet_cel_vf = sum(internet_cel_per), by(year)

* Gráfico de Tendencia: Pagos Digitales
twoway (line internet_cel_vf year, lc(navy*.8) lw(medthick)), ///
ylabel(0(2)10, angle(0)) ytitle("Porcentaje (%)") ///
xtitle("Año") title("Adopción de Pagos Digitales (ENAHO)") ///
graphregion(color(white))
    
graph export "$result/trend_digital_payments.pdf", replace
restore

save "$output/payment_methods_final", replace
