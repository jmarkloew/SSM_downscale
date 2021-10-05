Model output (f�r jede Bodentiefe des SWI Produkts)

pro Zeitpunkt der S1-Daten (insgesamt 23, �ber alle Pixel) wurde eine lineare Regression mit folgender Gleichung durchgef�hrt:

SWI ~ S1 + aspect + convergence + elevation + slope + twi + ndvi_mean + ndvi_sd + ndwi_mean + ndwi_sd

F�r jedes Modell wurden folgende Parameter in die csv Datei ausgeschrieben:

- adjusted R� des Modells
- p value des Modells
- p values der einzelnen Koeffizienten/Variablen (p_*Name Variable*)
- Werte der Koeffizienten der Variablen (beta_*Name Variable*)



Corr_lm_raster (f�r jede Bodentiefe des SWI Produkts):

f�r jedes Pixel (�ber alle Zeitpunkte) wurde eine lineare Regression mit folgender Gleichung durchgef�hrt:

SWI ~ S1

F�r jedes Pixel (jedes Modell) wurden folgende Parameter in ein Raster ausgeschrieben:

- Korrelationskoeffizient (Pearson) (au�erhalb des Modells berechnet) (Layer 1 des Rasters)
- adjusted R� des Modells (Layer 2)
- p value des Modells (Layer 3)


Zus�tzlicher Hinweis: Werte <2.2e-16 gelten als 0.


