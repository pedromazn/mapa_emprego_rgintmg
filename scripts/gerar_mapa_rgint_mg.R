# =========================================
# SALDO DE EMPREGOS POR REGIAO INTERMEDIARIA
# Minas Gerais | Novo Caged + geobr
# =========================================

required_packages <- c("readxl", "dplyr", "ggplot2", "geobr", "sf", "scales")

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "Instale os pacotes antes de executar: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(ggplot2)
  library(geobr)
  library(sf)
  library(scales)
})

normalize_text <- function(x) {
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  trimws(x)
}

pick_input_path <- function() {
  candidates <- c(
    file.path("dados", "saldo_de_emprego_nas_regioes.csv"),
    file.path("dados", "saldo_de_emprego_nas_regioes.xlsx"),
    "saldo_de_emprego_nas_regioes.xlsx"
  )

  existing <- candidates[file.exists(candidates)]

  if (length(existing) == 0) {
    stop(
      "Arquivo nao encontrado. Esperado em 'dados/saldo_de_emprego_nas_regioes.xlsx' ",
      "ou na raiz do projeto.",
      call. = FALSE
    )
  }

  existing[[1]]
}

read_input_data <- function(path) {
  extension <- tolower(tools::file_ext(path))

  if (extension == "csv") {
    return(read.csv(path, check.names = FALSE, encoding = "UTF-8"))
  }

  read_excel(path)
}

rename_region_column <- function(data) {
  normalized_names <- normalize_text(names(data))

  if ("Regioes" %in% names(data)) {
    return(data)
  }

  if ("Regioes" %in% normalized_names) {
    names(data)[which(normalized_names == "Regioes")[1]] <- "Regioes"
    return(data)
  }

  stop("A base precisa ter a coluna 'Regioes'.", call. = FALSE)
}

input_path <- pick_input_path()
output_dir <- "graficos"

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

base_rgint <- read_input_data(input_path) |>
  rename_region_column()

required_columns <- c("Regioes", "Saldo", "Ano")
missing_columns <- setdiff(required_columns, names(base_rgint))

if (length(missing_columns) > 0) {
  stop(
    "Colunas ausentes na base: ",
    paste(missing_columns, collapse = ", "),
    call. = FALSE
  )
}

base_rgint <- base_rgint |>
  mutate(
    Regioes = as.character(Regioes),
    Saldo = gsub("\\.", "", as.character(Saldo)),
    Saldo = as.numeric(gsub(",", ".", Saldo)),
    Ano = as.integer(Ano)
  ) |>
  filter(!is.na(Regioes), !is.na(Saldo), !is.na(Ano))

ano_referencia <- max(base_rgint$Ano, na.rm = TRUE)

saldo_ano <- base_rgint |>
  filter(Ano == ano_referencia) |>
  group_by(Regioes) |>
  summarise(total_saldo = sum(Saldo, na.rm = TRUE), .groups = "drop") |>
  filter(normalize_text(Regioes) != "Minas Gerais") |>
  mutate(regiao_chave = normalize_text(Regioes))

rgint_mg <- geobr::read_intermediate_region(year = 2020) |>
  (\(x) {
    if (is.null(x)) {
      stop(
        "Nao foi possivel obter a malha geografica do geobr. ",
        "Verifique a conexao com a internet ou se a malha ja esta em cache.",
        call. = FALSE
      )
    }

    x
  })() |>
  filter(abbrev_state == "MG") |>
  transmute(
    regiao_mapa = name_intermediate,
    regiao_chave = normalize_text(name_intermediate),
    geometry = geom
  ) |>
  st_as_sf()

mapa_final <- rgint_mg |>
  left_join(saldo_ano, by = "regiao_chave") |>
  mutate(
    total_saldo = ifelse(is.na(total_saldo), 0, total_saldo),
    label = paste0(
      regiao_mapa,
      "\n",
      label_number(big.mark = ".", decimal.mark = ",")(total_saldo)
    )
  )

output_path <- file.path(output_dir, paste0("mapa_rgint_mg_", ano_referencia, ".png"))

g_mapa <- ggplot(st_transform(mapa_final, 5880)) +
  geom_sf(aes(fill = total_saldo), color = "#ffffff", linewidth = 0.4) +
  geom_sf_text(
    aes(label = label),
    size = 3.2,
    fontface = "bold",
    color = "#111111",
    lineheight = 0.9,
    check_overlap = TRUE
  ) +
  scale_fill_gradient2(
    low = "#b71c1c",
    mid = "#f5f5f5",
    high = "#0d47a1",
    midpoint = 0,
    labels = label_number(big.mark = ".", decimal.mark = ","),
    name = "Saldo"
  ) +
  labs(
    title = "Saldo de empregos por regiao intermediaria",
    subtitle = paste("Minas Gerais | ano de referencia:", ano_referencia),
    caption = "Fonte: elaboracao propria com base agregada do Novo Caged e malha do geobr/IBGE"
  ) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "#fafafa", color = NA),
    panel.background = element_rect(fill = "#fafafa", color = NA),
    plot.title = element_text(size = 20, face = "bold", hjust = 0.5, color = "#1a1a1a"),
    plot.subtitle = element_text(size = 12, hjust = 0.5, color = "#4f4f4f"),
    plot.caption = element_text(size = 9, hjust = 0.5, color = "#666666"),
    legend.position = "bottom",
    legend.title = element_text(face = "bold")
  ) +
  guides(fill = guide_colorbar(title.position = "top", title.hjust = 0.5))

ggsave(
  filename = output_path,
  plot = g_mapa,
  width = 12,
  height = 14,
  dpi = 300,
  bg = "#fafafa"
)

message("Mapa salvo em: ", normalizePath(output_path, winslash = "/", mustWork = FALSE))
