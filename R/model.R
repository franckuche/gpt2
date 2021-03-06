gpt2_run <- function(prompt = "Hello my name is",
                     model = c("124M", "355M", "774M", "1558M"),
                     seed = NULL,
                     batch_size = 1,
                     total_tokens = NULL,
                     temperature = 1,
                     top_k = 0,
                     top_p = 1) {
  model <- match.arg(model, choices = c("124M", "355M", "774M", "1558M"))
  install_gpt2_verify()

  pin_name <- paste("gpt2", model, sep = "_")
  if (nrow(pins::pin_find(name = pin_name, board = "local")) == 0) gpt2_download(model = model)

  py_path <- system.file("python", package = "gpt2")
  py_gpt2 <- reticulate::import_from_path("gpt2", path = py_path)

  model_path <- dirname(dirname(pins::pin_get(name = pin_name, board = "local")[1]))
  encoder <- py_gpt2$encoder$get_encoder(pin_name, model_path)
  gpt2 <- py_gpt2$gpt2

  hparams <- gpt2$default_hparams()

  hparams_json <- paste0(readLines(file.path(model_path, pin_name, "hparams.json")), collapse = "\n")
  json <- reticulate::import("json")
  hparams <- json$loads(hparams_json)

  if (is.null(total_tokens)) {
    total_tokens <- hparams$n_ctx
  }

  np <- reticulate::import("numpy")
  tf <- tensorflow::tf

  with(tf$compat$v1$Session(graph = tf$Graph()) %as% sess, {
    tf$compat$v1$disable_eager_execution()

    if (!is.null(seed)) {
      seed <- as.integer(seed)
      np$random$seed(seed)
      tf$compat$v1$set_random_seed(seed)
    }

    context <- tf$compat$v1$placeholder(tf$int32, list(batch_size, NULL))

    context_tokens <- encoder$encode(prompt)

    output <- gpt2$sample_sequence(
      hparams = hparams,
      length = min(total_tokens, 1023 - length(context_tokens)),
      context = context,
      batch_size = as.integer(batch_size),
      temperature = temperature,
      top_k = as.integer(top_k),
      top_p = as.integer(top_p)
    )

    saver <- tf$compat$v1$train$Saver()
    ckpt <- tf$compat$v1$train$latest_checkpoint(file.path(model_path, pin_name))
    saver$restore(sess, ckpt)

    out <- sess$run(output, feed_dict = reticulate::dict(
      context = list(context_tokens)
    ))

    generated <- out[1:nrow(out), (length(context_tokens)+1):ncol(out)]
    # workaround to avoid "int is not iterable" error when length == 1
    decoded <- encoder$decode(if (length(generated) == 1) c(generated, generated) else generated)
    if (length(generated) == 1) strsplit(decoded, "")[[1]][1] else decoded
  })
}

#' Evaluate Model
#'
#' Evaluates the GPT-2 model which generates tokens based on the given prompt.
#'
#' @param propmt The prompt to use to generate tokens from.
#' @param model The size of the model to load: \code{"124M"}, \code{"355M"},
#'   \code{"774M"} or \code{"1558M"}.
#' @param seed Integer seed for random number generators, fix seed to
#'   reproduce results.
#' @param batch_size Number of batches (only affects speed/memory).
#' @param total_tokens Number of tokens in generated text, if \code{NULL} (default),
#'   is determined by model hyperparameters.
#' @param temperature Numeric value controlling randomness in boltzmann
#'   distribution. Lower temperature results in less random completions. As the
#'   temperature approaches zero, the model will become deterministic and
#'   repetitive. Higher temperature results in more random completions.
#' @param top_k Integer value controlling diversity. 1 means only 1 word is considered
#'   for each step (token), resulting in deterministic completions.
#' @param top_p cutoff for nucleus sampling.
#'
#' @importFrom reticulate %as%
#' @export
gpt2 <- function(prompt = "Hello my name is",
                 model = c("124M", "345M", "774M", "1558M"),
                 seed = NULL,
                 batch_size = 1,
                 total_tokens = NULL,
                 temperature = 1,
                 top_k = 0,
                 top_p = 1) {
  sapply(prompt, function(prompt) gpt2_run(
    prompt,
    model = model,
    seed = seed,
    batch_size = batch_size,
    total_tokens = total_tokens,
    temperature = temperature,
    top_k = top_k,
    top_p =  as.integer(top_p)
  ))
}
