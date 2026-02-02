resource "aws_iam_group" "vice_admiral" {
  name = "Vice-Admirals-Noise2Signal-LLC"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "administrator" {
  group      = aws_iam_group.vice_admiral.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


resource "aws_iam_user" "vice_admiral" {
  name          = "Vice-Admiral-Noise2Signal-LLC"
  path          = "/"
  force_destroy = true

  tags = {
    Purpose = "Access"
  }
}

data "aws_iam_policy" "change_password" {
  name = "IAMUserChangePassword"
}

resource "aws_iam_user_policy_attachment" "change_password" {
  user       = aws_iam_user.vice_admiral.name
  policy_arn = data.aws_iam_policy.change_password.arn
}

resource "aws_iam_user_group_membership" "vice_admiral" {
  user = aws_iam_user.vice_admiral.name

  groups = [
    aws_iam_group.vice_admiral.name,
  ]
}
