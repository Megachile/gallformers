defmodule Gallformers.Authorship do
  @moduledoc """
  Taxonomic authorship for species names and their scientific synonyms.

  The domain rule this context exists to encode: author and year attach to a
  name's *original description*, never to a later usage of that name. A source
  that merely uses a combination contributes nothing to its authorship.

  Classification and derivation live in `Gallformers.Authorship.Classifier`,
  which is pure. This module is the boundary anchor and will hold the
  persistence API.
  """

  use Boundary, deps: [Gallformers.TaxonName], exports: :all
end
