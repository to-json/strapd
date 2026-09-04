# Set identification from install inputs
if [[ -n ${STRAPD_USER_NAME//[[:space:]]/} ]]; then
  git config --global user.name "$STRAPD_USER_NAME"
fi

if [[ -n ${STRAPD_USER_EMAIL//[[:space:]]/} ]]; then
  git config --global user.email "$STRAPD_USER_EMAIL"
fi
