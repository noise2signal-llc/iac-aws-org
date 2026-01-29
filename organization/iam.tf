resource "aws_iam_group" "admirals" {
  name = "Noise2Signal-LLC-Admirals"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "admirals_admin" {
  group      = aws_iam_group.admirals.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user" "admiral" {
  name = "admiral-noise2signal-llc"
  path = "/"
  force_destroy = true

  tags = {
    Purpose = "Access"
  }
}

resource "aws_iam_user_group_membership" "admiral_membership" {
  user = aws_iam_user.admiral.name

  groups = [
    aws_iam_group.admirals.name,
  ]
}
