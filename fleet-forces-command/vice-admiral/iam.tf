resource "aws_iam_group" "admirals" {
  name = "Noise2Signal-LLC-Admirals"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "admirals_admin" {
  group      = aws_iam_group.admirals.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user" "admiral" {
  name          = "admiral-noise2signal-llc"
  path          = "/"
  force_destroy = true

  tags = {
    Purpose = "Access"
  }
}

resource "aws_iam_user_policy_attachment" "admiral_import" {
  user       = aws_iam_user.admiral.name
  policy_arn = data.aws_iam_policy.change_password.arn
}

resource "aws_iam_user_group_membership" "admiral_membership" {
  user = aws_iam_user.admiral.name

  groups = [
    aws_iam_group.admirals.name,
  ]
}

####  ^^^ DELETE
####---------------------------------------------------------------------
####  vvv KEEP


resource "aws_iam_group" "viceadmiral" {
  name = "ViceAdmirals-Noise2Signal-LLC"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "viceadmiral" {
  group      = aws_iam_group.viceadmiral.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


resource "aws_iam_user" "viceadmiral" {
  name          = "viceadmiral-noise2signal-llc"
  path          = "/"
  force_destroy = true

  tags = {
    Purpose = "Access"
  }
}

data "aws_iam_policy" "change_password" {
  name = "IAMUserChangePassword"
}

resource "aws_iam_user_policy_attachment" "viceadmiral" {
  user       = aws_iam_user.viceadmiral.name
  policy_arn = data.aws_iam_policy.change_password.arn
}

resource "aws_iam_user_group_membership" "viceadmiral" {
  user = aws_iam_user.viceadmiral.name

  groups = [
    aws_iam_group.viceadmiral.name,
  ]
}
