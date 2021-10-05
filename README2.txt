Model output (für jede Bodentiefe des SWI Produkts)

pro Zeitpunkt der S1-Daten (insgesamt 23, über alle Pixel) wurde eine lineare Regression mit folgender Gleichung durchgeführt:

SWI ~ S1 + aspect + convergence + elevation + slope + twi + ndvi_mean + ndvi_sd + ndwi_mean + ndwi_sd

Für jedes Modell wurden folgende Parameter in die csv Datei ausgeschrieben:

- adjusted R² des Modells
- p value des Modells
- p values der einzelnen Koeffizienten/Variablen (p_*Name Variable*)
- Werte der Koeffizienten der Variablen (beta_*Name Variable*)



Corr_lm_raster (für jede Bodentiefe des SWI Produkts):

für jedes Pixel (über alle Zeitpunkte) wurde eine lineare Regression mit folgender Gleichung durchgeführt:

SWI ~ S1

Für jedes Pixel (jedes Modell) wurden folgende Parameter in ein Raster ausgeschrieben:

- Korrelationskoeffizient (Pearson) (außerhalb des Modells berechnet) (Layer 1 des Rasters)
- adjusted R² des Modells (Layer 2)
- p value des Modells (Layer 3)


Zusätzlicher Hinweis: Werte <2.2e-16 gelten als 0.


