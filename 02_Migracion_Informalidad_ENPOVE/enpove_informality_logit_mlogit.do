clear all
set more off
set seed 777  // Para reproducibilidad de la partición 
cd "C:\Users\asus\Desktop\trabajo_enpove"

*Debido al límite de mi versión de STATA 15 (máximo 2048 variables), debo reducir la data para hacer merge posteriormente

use "992-Modulo2020\enahopv01-2024-200.dta", clear
keep conglome vivienda hogar codperso p207 p208a p209 factor
save "m200_l.dta", replace

use "992-Modulo2021\enahopv01a-2024-300.dta", clear
keep conglome vivienda hogar codperso p300b p301a p301d1
save "m300_l.dta", replace

use "992-Modulo2023\enahopv01a-2024-500.dta", clear
keep conglome vivienda hogar codperso ocu500 ocupinf p507 p510 p513t
save "m500_l.dta", replace

use "992-Modulo2041\enahopv01a-2024-1000.dta", clear
keep conglome vivienda hogar codperso p1002
save "m1000_l.dta", replace

use "992-Modulo2037\sumariapv-2024-12g.dta", clear
keep conglome vivienda hogar ubigeo dominio estrato pobreza factor
save "sumaria_l.dta", replace

*Unión final
use "m200_l.dta", clear
foreach m in m300_l m500_l m1000_l {
merge 1:1 conglome vivienda hogar codperso using "`m'", nogen
}
merge m:1 conglome vivienda hogar using "sumaria_l.dta", nogen

*Nos quedamos solo con la población que labora (ya sea informal o formalmente) y que es PEA
keep if ocu500 == 1 & p208a >= 14
drop if ocupinf == . | p507 == . // No relevante porque no hay missing values

* Y Binaria: 1=Informal, 0=Formal
gen informal = (ocupinf == 1)
label define linf 1 "Informal" 0 "Formal"
label values informal linf

*Y Multinomial: 
gen cat_multi = .
replace cat_multi = 1 if (p507==3 | p507==4) & informal == 0 // Asal. Formal
replace cat_multi = 2 if (p507==3 | p507==4) & informal == 1 // Asal. Informal
replace cat_multi = 3 if (p507==1 | p507==2) & informal == 0 // Indep. Formal
replace cat_multi = 4 if (p507==1 | p507==2) & informal == 1 // Indep. Informal
label define lm 1 "Asal. Form" 2 "Asal. Inf" 3 "Ind. Form" 4 "Ind. Inf"
label values cat_multi lm

* X's (Explicativas)
gen mujer = (p207 == 2)
gen edad = p208a
gen edad2 = edad^2
gen tiene_permiso = (p1002 <= 4)

*Educación Superior en Perú
gen ed_sup_peru = (p301a >= 7 & p301a <= 11)

*Educación Superior en Venezuela con título homologado
gen ed_sup_vzla_homol = (p300b >= 7 & p300b <= 11) & (p301d1 == 1)

*Educación Superior en Venezuela sin homologar
gen ed_sup_vzla_no_homol = (p300b >= 7 & p300b <= 11) & (p301d1 == 2)

label var ed_sup_peru "Sup. Perú"
label var ed_sup_vzla_homol "Sup. VZLA Homologado"
label var ed_sup_vzla_no_homol "Sup. VZLA No Homologado"

*Distribución de Y
tab cat_multi [iw=factor] 

global controles mujer edad ed_sup_peru ed_sup_vzla_homol ed_sup_vzla_no_homol tiene_permiso

*General
summarize informal $controles [aw=factor]

*Por categoría 
tabstat $controles, by(cat_multi) stat(mean)


*PARTICIÓN TRAIN/TEST (80/20)
gen univ = runiform()
gen train = (univ <= 0.80)
label define lt 1 "Entrenamiento" 0 "Prueba"
label values train lt

*

*Estimación modelos binarios 
logit informal $controles if train == 1, vce(robust)
estimates store m_logit

probit informal $controles if train == 1, vce(robust)
estimates store m_probit

*Tabla de coeficientes (Logit vs Probit)
esttab m_logit m_probit using tabla_coef.tex, replace ///
label star(* 0.10 ** 0.05 *** 0.01) b(3) se(3) ///
booktabs title("Comparación Logit vs Probit") mtitle("Logit" "Probit")

*Inferencia 

test ed_sup_peru ed_sup_vzla_homol ed_sup_vzla_no_homol
local p_conjunto = r(p)
display "El p-valor para la significancia conjunta de educación es: " `p_conjunto'

*Efectos Marginales AME
estimates restore m_logit
margins, dydx(*) post
estimates store ame_logit

*Tabla de efectos marginales
esttab ame_logit using tabla_marg.tex, replace ///
label b(3) se(3) booktabs ///
title("Efectos Marginales Promedio (AME)")

*Modelo Multinomial
mlogit cat_multi $controles if train == 1, base(1) vce(robust)
estimates store m_mlogit

*EVALUACIÓN PREDICCIÓN (OUT-OF-SAMPLE)
estimates restore m_logit
predict p_hat if train == 0
gen y_pred = (p_hat > 0.5) if train == 0 & p_hat != .

*Matriz de confusión
tab informal y_pred if train == 0, cell

*Cálculo accuracy
gen acierto = (informal == y_pred) if train == 0 & y_pred != .
summarize acierto if train == 0
global total_accuracy = r(mean)

display "El Accuracy real en la muestra de prueba es: " $total_accuracy
