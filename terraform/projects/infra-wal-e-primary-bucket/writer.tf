/**
* ## Project: wal-e-primary-bucket
*
* Create a policy that allows writing of the database-backups bucket. This
* doesn't create a role as the calling instance is assumed to already
* have one which should be attached to this policy.
*
*/

resource "aws_iam_policy" "wal_e_primary_writer" {
  name        = "govuk-${var.aws_environment}-wal_e_primary-writer-policy"
  policy      = "${data.aws_iam_policy_document.wal_e_primary_writer.json}"
  description = "Allows writing of the database_backups bucket"
}

data "aws_iam_policy_document" "wal_e_primary_writer" {
  statement {
    sid = "ReadBucketLists"

    actions = [
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
    ]

    # In theory referencing the bucket ARN should work but it doesn't so use * instead
    resources = [
      "arn:aws:s3:::*",
    ]
  }

  statement {
    sid     = "WriteGovukWalEPrimaryBackups"
    actions = ["s3:*"]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.wal_e_primary.id}",
      "arn:aws:s3:::${aws_s3_bucket.wal_e_primary.id}/*",
    ]
  }
}

resource "aws_iam_user" "wal_e_primary_writer" {
  name = "govuk-${var.aws_environment}-wal-e-primary-writer"
}

resource "aws_iam_policy_attachment" "wal_e_primary_writer" {
  name       = "wal_e_primary_writer-policy-attachment"
  users      = ["${aws_iam_user.wal_e_primary_writer.name}"]
  policy_arn = "${aws_iam_policy.wal_e_primary_writer.arn}"
}

output "write_wal_e_primary_policy_arn" {
  value       = "${aws_iam_policy.wal_e_primary_writer.arn}"
  description = "ARN of the write wal_e_primary-bucket policy"
}
